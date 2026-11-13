use crate::{monitor::controller, state::AppSnapshot};
use std::{collections::HashMap, sync::Mutex, time::Duration};
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_opener::OpenerExt;

pub fn open_window(app: &AppHandle) {
    #[cfg(target_os = "macos")]
    let _ = app.set_activation_policy(tauri::ActivationPolicy::Regular);
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

/// Codex 与 Antigravity 各占一个独立状态项，以品牌图标区分服务，标题只显示额度。
const CODEX_TRAY: &str = "codex";
const ANTIGRAVITY_TRAY: &str = "antigravity";
const TRAY_ICONS: [(&str, &[u8]); 2] = [
    (ANTIGRAVITY_TRAY, include_bytes!("../icons/tray-antigravity.png")),
    (CODEX_TRAY, include_bytes!("../icons/tray-codex.png")),
];

/// 解码单色托盘图标；`white` 为真时保留透明度、把像素改为白色，供深色任务栏使用。
fn tray_icon(bytes: &[u8], white: bool) -> tauri::Result<tauri::image::Image<'static>> {
    let image = tauri::image::Image::from_bytes(bytes)?;
    if !white {
        return Ok(image.to_owned());
    }
    let mut rgba = image.rgba().to_vec();
    for pixel in rgba.chunks_exact_mut(4) {
        pixel[..3].fill(255);
    }
    Ok(tauri::image::Image::new_owned(rgba, image.width(), image.height()))
}

/// Windows 托盘图标不支持模板着色，按任务栏（系统）主题切换黑 / 白图标。
#[cfg(windows)]
pub mod taskbar_theme {
    use super::*;
    use std::sync::atomic::{AtomicU8, Ordering};

    /// 已应用的图标状态：0 未应用，1 黑色（浅色任务栏），2 白色（深色任务栏）。
    static APPLIED: AtomicU8 = AtomicU8::new(0);

    /// 任务栏颜色跟随 `SystemUsesLightTheme`，而非应用主题；读取失败或缺失时按深色处理（旧版 Windows 10 默认深色任务栏）。
    fn taskbar_is_dark() -> bool {
        use windows_sys::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_DWORD};
        let key: Vec<u16> = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize\0".encode_utf16().collect();
        let name: Vec<u16> = "SystemUsesLightTheme\0".encode_utf16().collect();
        let mut value: u32 = 0;
        let mut size = std::mem::size_of::<u32>() as u32;
        let status = unsafe {
            RegGetValueW(
                HKEY_CURRENT_USER,
                key.as_ptr(),
                name.as_ptr(),
                RRF_RT_REG_DWORD,
                std::ptr::null_mut(),
                (&mut value as *mut u32).cast(),
                &mut size,
            )
        };
        status != 0 || value == 0
    }

    /// 读取任务栏主题，仅在变化时替换两个托盘图标。
    pub fn sync(app: &AppHandle) {
        let dark = taskbar_is_dark();
        let state = if dark { 2 } else { 1 };
        if APPLIED.swap(state, Ordering::Relaxed) == state {
            return;
        }
        for (id, bytes) in TRAY_ICONS {
            if let (Some(tray), Ok(icon)) = (app.tray_by_id(id), tray_icon(bytes, dark)) {
                let _ = tray.set_icon(Some(icon));
            }
        }
    }
}

pub fn update_tray(app: &AppHandle, snapshot: &AppSnapshot) {
    let codex_visible = snapshot.settings.show_tray && snapshot.settings.monitoring_enabled;
    let antigravity_visible = snapshot.settings.antigravity_show_tray && snapshot.settings.antigravity_enabled;
    // 系统主题切换不一定触发窗口主题事件，随每次托盘更新复查任务栏颜色。
    #[cfg(windows)]
    taskbar_theme::sync(app);
    if let Some(tray) = app.tray_by_id(CODEX_TRAY) {
        let _ = tray.set_visible(codex_visible);
        if codex_visible {
            let content = codex_tray_content(snapshot);
            apply_tray_content(app, &tray, "Codex", content);
        } else {
            app.state::<TrayCountdowns>().0.lock().unwrap().remove("Codex");
        }
    }
    if let Some(tray) = app.tray_by_id(ANTIGRAVITY_TRAY) {
        let _ = tray.set_visible(antigravity_visible);
        if antigravity_visible {
            let content = antigravity_tray_content(snapshot);
            apply_tray_content(app, &tray, "Antigravity", content);
        } else {
            app.state::<TrayCountdowns>().0.lock().unwrap().remove("Antigravity");
        }
    }
    #[cfg(target_os = "macos")]
    {
        // 窗口隐藏时，有任一菜单栏入口才隐藏 Dock 图标。
        let hidden = app
            .get_webview_window("main")
            .is_some_and(|w| !w.is_visible().unwrap_or(true));
        if hidden {
            let _ = app.set_activation_policy(if codex_visible || antigravity_visible {
                tauri::ActivationPolicy::Accessory
            } else {
                tauri::ActivationPolicy::Regular
            });
        }
    }
}

/// 托盘下拉菜单中各个条目的规格说明
enum TrayMenuItemSpec {
    /// 带有彩色进度条的额度行，点击可唤起主面板
    Quota {
        id: String,
        label: String,
        remaining_percent: Option<f64>,
    },
    /// 可点击的辅助信息行（如重置卡数量），点击唤起面板
    ActionNote(String),
    Deadline { label: String, timestamp: Option<f64>, expires: bool },
    /// 静态只读信息行（如错误、提示或刷新状态）
    Info(String),
}

struct TrayContent {
    title: String,
    tooltip: String,
    items: Vec<TrayMenuItemSpec>,
}

#[derive(Default)]
struct TrayCountdowns(Mutex<HashMap<String, Vec<TrayCountdown>>>);

struct TrayCountdown {
    item: tauri::menu::MenuItem<tauri::Wry>,
    label: String,
    timestamp: Option<f64>,
    expires: bool,
    text: String,
}

fn deadline_text(label: &str, timestamp: Option<f64>, expires: bool, now: f64) -> String {
    let action = if expires { "到期" } else { "重置" };
    let prefix = if label.is_empty() { String::new() } else { format!("{label} · ") };
    let Some(date) = timestamp.and_then(|time| chrono::DateTime::from_timestamp(time as i64, 0)) else {
        return format!("{prefix}{action}时间未知");
    };
    let remaining = (timestamp.unwrap() - now).ceil().max(0.0) as u64;
    let duration = if remaining == 0 {
        if expires { "已到期".into() } else { "等待实际重置".into() }
    } else {
        let value = if remaining > 86400 {
            format!("{} 天 {} 小时", remaining / 86400, remaining % 86400 / 3600)
        } else if remaining > 3600 {
            format!("{} 小时 {:02} 分", remaining / 3600, remaining % 3600 / 60)
        } else {
            format!("{} 分 {:02} 秒", remaining / 60, remaining % 60)
        };
        format!("{value}后{action}")
    };
    format!("{prefix}{duration} · {}", date.with_timezone(&chrono::Local).format("%m-%d %H:%M"))
}

/// 绘制菜单项中的彩色胶囊/环形进度条图标。
/// macOS 上生成 88×36 像素（Retina 对应 44×18 pt 菜单项）的圆角胶囊进度条；
/// 非 macOS（如 Windows）上生成 32×32 像素（对应 16×16 pt）的迷你环形进度圈。
fn create_progress_capsule_icon(remaining_percent: Option<f64>) -> tauri::image::Image<'static> {
    #[cfg(target_os = "macos")]
    {
        const WIDTH: usize = 88;
        const HEIGHT: usize = 36;
        let mut rgba = vec![0u8; WIDTH * HEIGHT * 4];

        // 胶囊几何参数：水平宽度 84px，高度 14px，圆角半径 7px，垂直居中
        let x_start = 2.0_f64;
        let x_end = 86.0_f64;
        let bar_width = x_end - x_start;
        let radius = 7.0_f64;
        let y_center = 18.0_f64;
        let seg_x0 = x_start + radius;
        let seg_x1 = x_end - radius;

        let (fill_w, fill_color) = match remaining_percent {
            Some(p) => {
                let clamped = p.clamp(0.0, 100.0);
                let fill = bar_width * (clamped / 100.0);
                // 状态色统一遵循设计系统：<=20% 警示红；<=50% 预警橙；>50% 优雅主蓝
                let color = if clamped <= 20.0 {
                    (220u8, 53u8, 69u8)
                } else if clamped <= 50.0 {
                    (217u8, 119u8, 6u8)
                } else {
                    (49u8, 120u8, 183u8)
                };
                (fill, Some(color))
            }
            None => (0.0, None),
        };

        let track_color = (135u8, 140u8, 150u8);
        let track_base_alpha = 0.28_f64;

        for py in 0..HEIGHT {
            for px in 0..WIDTH {
                let x = px as f64 + 0.5;
                let y = py as f64 + 0.5;

                let clamped_x = x.clamp(seg_x0, seg_x1);
                let dx = x - clamped_x;
                let dy = y - y_center;
                let dist = (dx * dx + dy * dy).sqrt();

                let sdf_track = dist - radius;
                let alpha_track = (0.5 - sdf_track).clamp(0.0, 1.0);
                if alpha_track <= 0.0 {
                    continue;
                }

                let fill_alpha = if fill_color.is_some() {
                    if fill_w >= bar_width {
                        alpha_track
                    } else if fill_w <= 0.0 {
                        0.0
                    } else {
                        let fill_x = x_start + fill_w;
                        let cutoff_alpha = (fill_x - x + 0.5).clamp(0.0, 1.0);
                        alpha_track * cutoff_alpha
                    }
                } else {
                    0.0
                };

                let track_a = track_base_alpha * alpha_track;
                let fill_a = 0.95_f64 * fill_alpha;

                let (out_r, out_g, out_b, out_a) = if fill_a > 0.0 {
                    let (fr, fg, fb) = fill_color.unwrap();
                    let combined_a = fill_a + track_a * (1.0 - fill_a);
                    let r = (fr as f64 * fill_a + track_color.0 as f64 * track_a * (1.0 - fill_a)) / combined_a;
                    let g = (fg as f64 * fill_a + track_color.1 as f64 * track_a * (1.0 - fill_a)) / combined_a;
                    let b = (fb as f64 * fill_a + track_color.2 as f64 * track_a * (1.0 - fill_a)) / combined_a;
                    (r, g, b, combined_a)
                } else {
                    (track_color.0 as f64, track_color.1 as f64, track_color.2 as f64, track_a)
                };

                let idx = (py * WIDTH + px) * 4;
                rgba[idx] = out_r.round() as u8;
                rgba[idx + 1] = out_g.round() as u8;
                rgba[idx + 2] = out_b.round() as u8;
                rgba[idx + 3] = (out_a * 255.0).round().clamp(0.0, 255.0) as u8;
            }
        }

        tauri::image::Image::new_owned(rgba, WIDTH as u32, HEIGHT as u32)
    }

    #[cfg(not(target_os = "macos"))]
    {
        const SIZE: usize = 32;
        let mut rgba = vec![0u8; SIZE * SIZE * 4];
        let center = 16.0_f64;
        let r_mid = 10.0_f64;
        let half_width = 2.5_f64;

        let (fill_frac, fill_color) = match remaining_percent {
            Some(p) => {
                let clamped = p.clamp(0.0, 100.0);
                let color = if clamped <= 20.0 {
                    (220u8, 53u8, 69u8)
                } else if clamped <= 50.0 {
                    (217u8, 119u8, 6u8)
                } else {
                    (49u8, 120u8, 183u8)
                };
                (clamped / 100.0, Some(color))
            }
            None => (0.0, None),
        };

        let track_color = (135u8, 140u8, 150u8);
        let track_base_alpha = 0.35_f64;

        for py in 0..SIZE {
            for px in 0..SIZE {
                let x = px as f64 + 0.5;
                let y = py as f64 + 0.5;

                let dx = x - center;
                let dy = y - center;
                let dist = (dx * dx + dy * dy).sqrt();

                let sdf_ring = (dist - r_mid).abs() - half_width;
                let alpha_ring = (0.5 - sdf_ring).clamp(0.0, 1.0);
                if alpha_ring <= 0.0 {
                    continue;
                }

                let angle = (-dy).atan2(-dx) + std::f64::consts::PI;
                let frac = ((angle + std::f64::consts::FRAC_PI_2) % (2.0 * std::f64::consts::PI)) / (2.0 * std::f64::consts::PI);

                let fill_alpha = if fill_color.is_some() && frac <= fill_frac {
                    alpha_ring
                } else {
                    0.0
                };

                let track_a = track_base_alpha * alpha_ring;
                let fill_a = 0.95_f64 * fill_alpha;

                let (out_r, out_g, out_b, out_a) = if fill_a > 0.0 {
                    let (fr, fg, fb) = fill_color.unwrap();
                    let combined_a = fill_a + track_a * (1.0 - fill_a);
                    let r = (fr as f64 * fill_a + track_color.0 as f64 * track_a * (1.0 - fill_a)) / combined_a;
                    let g = (fg as f64 * fill_a + track_color.1 as f64 * track_a * (1.0 - fill_a)) / combined_a;
                    let b = (fb as f64 * fill_a + track_color.2 as f64 * track_a * (1.0 - fill_a)) / combined_a;
                    (r, g, b, combined_a)
                } else {
                    (track_color.0 as f64, track_color.1 as f64, track_color.2 as f64, track_a)
                };

                let idx = (py * SIZE + px) * 4;
                rgba[idx] = out_r.round() as u8;
                rgba[idx + 1] = out_g.round() as u8;
                rgba[idx + 2] = out_b.round() as u8;
                rgba[idx + 3] = (out_a * 255.0).round().clamp(0.0, 255.0) as u8;
            }
        }

        tauri::image::Image::new_owned(rgba, SIZE as u32, SIZE as u32)
    }
}

fn codex_tray_content(snapshot: &AppSnapshot) -> TrayContent {
    let has_codex = snapshot.quota.windows.iter().any(|window| window.bucket == "codex");
    let mut windows = snapshot.quota.windows.iter()
        .filter(|window| !has_codex || window.bucket == "codex")
        .collect::<Vec<_>>();
    windows.sort_by_key(|window| window.duration_minutes.unwrap_or(i64::MAX));
    let mut title = if windows.is_empty() {
        "--".into()
    } else {
        windows
            .iter()
            .take(2)
            .map(|window| format!("{}%", window.remaining().floor() as u64))
            .collect::<Vec<_>>()
            .join(" ")
    };
    if snapshot.quota.error.is_some() {
        title.push_str(" !");
    }

    let mut items = Vec::new();
    let mut tooltip_lines = Vec::new();

    if windows.is_empty() {
        items.push(TrayMenuItemSpec::Info("等待额度数据".into()));
        tooltip_lines.push("等待额度数据".into());
    } else {
        for window in &windows {
            let name = if window.bucket == "codex" {
                window.display_label()
            } else {
                format!("{} · {}", window.name, window.display_label())
            };
            let remaining = window.remaining().floor() as u64;
            let reset_str = window.resets_at
                .and_then(|timestamp| chrono::DateTime::from_timestamp(timestamp as i64, 0))
                .map(|date| format!(" · {} 重置", date.with_timezone(&chrono::Local).format("%m-%d %H:%M")))
                .unwrap_or_default();

            items.push(TrayMenuItemSpec::Quota {
                id: format!("open:quota:codex:{}", window.id),
                label: format!("{name} · 剩余 {remaining}%"),
                remaining_percent: Some(window.remaining()),
            });
            items.push(TrayMenuItemSpec::Deadline { label: String::new(), timestamp: window.resets_at, expires: false });

            tooltip_lines.push(format!("{name}：剩余 {remaining}%{reset_str}"));
        }
    }

    if let Some(credits) = &snapshot.quota.reset_credits {
        if credits.available_count > 0 {
            items.push(TrayMenuItemSpec::ActionNote(format!("重置卡 · {} 张可用", credits.available_count)));
            tooltip_lines.push(format!("可用重置卡：{} 张", credits.available_count));
            let available = credits.available_credits();
            for (index, credit) in available.iter().enumerate() {
                items.push(TrayMenuItemSpec::Deadline {
                    label: format!("重置卡 {}", index + 1), timestamp: credit.expires_at, expires: true,
                });
            }
            if (available.len() as u64) < credits.available_count {
                items.push(TrayMenuItemSpec::Info("到期明细不完整".into()));
            }
        }
    }

    if let Some(error) = &snapshot.quota.error {
        items.push(TrayMenuItemSpec::Info(format!("⚠️ 额度可能已过期：{error}")));
        tooltip_lines.push(format!("额度可能已过期：{error}"));
    }

    TrayContent {
        title,
        tooltip: format!("Codex Quota · Codex\n{}", tooltip_lines.join("\n")),
        items,
    }
}

fn antigravity_tray_content(snapshot: &AppSnapshot) -> TrayContent {
    let quota = &snapshot.antigravity;
    let buckets: Vec<_> = quota.groups.iter().flat_map(|group| &group.buckets).filter(|bucket| !bucket.disabled).collect();
    let minimum = buckets.iter().filter_map(|bucket| bucket.remaining_percent).reduce(f64::min);
    let value = minimum.map(|value| format!("{}%", value.floor() as u64)).unwrap_or_else(|| "--".into());
    let status = if quota.error.is_some() { " !" } else if quota.refreshing { " …" } else if buckets.iter().any(|bucket| bucket.remaining_percent.is_none()) { " ?" } else { "" };
    let title = format!("{value}{status}");

    let mut items = Vec::new();
    let mut tooltip_lines = Vec::new();

    tooltip_lines.push(format!("最低已知剩余 {value}{status}"));

    for group in &quota.groups {
        for bucket in &group.buckets {
            let window = match bucket.window.as_deref() {
                Some("5h") => "五小时额度",
                Some("weekly") => "周额度",
                _ => "额度",
            };
            let reset_str = bucket.resets_at
                .and_then(|timestamp| chrono::DateTime::from_timestamp(timestamp as i64, 0))
                .map(|date| format!(" · {} 重置", date.with_timezone(&chrono::Local).format("%m-%d %H:%M")))
                .unwrap_or_default();

            let display_name = if group.name == bucket.name || group.name.is_empty() {
                bucket.name.clone()
            } else {
                format!("{} · {}", group.name, bucket.name)
            };

            if bucket.disabled {
                items.push(TrayMenuItemSpec::Quota {
                    id: format!("open:quota:ag:{}", bucket.id),
                    label: format!("{display_name} · {window} · 未启用"),
                    remaining_percent: None,
                });
                tooltip_lines.push(format!("{} · {window} · {} [{}]：未启用", group.name, bucket.name, bucket.id));
            } else if let Some(p) = bucket.remaining_percent {
                let rem_int = p.floor() as u64;
                items.push(TrayMenuItemSpec::Quota {
                    id: format!("open:quota:ag:{}", bucket.id),
                    label: format!("{display_name} · {window} · 剩余 {rem_int}%"),
                    remaining_percent: Some(p),
                });
                tooltip_lines.push(format!("{} · {window} · {} [{}]：剩余 {rem_int}%{reset_str}", group.name, bucket.name, bucket.id));
            } else {
                items.push(TrayMenuItemSpec::Quota {
                    id: format!("open:quota:ag:{}", bucket.id),
                    label: format!("{display_name} · {window} · 剩余未知"),
                    remaining_percent: None,
                });
                tooltip_lines.push(format!("{} · {window} · {} [{}]：剩余未知", group.name, bucket.name, bucket.id));
            }
            if !bucket.disabled {
                items.push(TrayMenuItemSpec::Deadline { label: String::new(), timestamp: bucket.resets_at, expires: false });
            }
        }
    }

    if let Some(error) = &quota.error {
        items.push(TrayMenuItemSpec::Info(format!("⚠️ Antigravity：{error}")));
        tooltip_lines.push(format!("Antigravity：{error}"));
    }

    if let Some(time) = quota.last_success.and_then(|timestamp| chrono::DateTime::from_timestamp(timestamp as i64, 0)) {
        let tag = if quota.error.is_some() { "（已过期）" } else { "" };
        let formatted = time.with_timezone(&chrono::Local).format("%m-%d %H:%M");
        items.push(TrayMenuItemSpec::Info(format!("上次读取{tag}：{formatted}")));
        tooltip_lines.push(format!("Antigravity 上次读取{tag}：{formatted}"));
    }

    TrayContent {
        title,
        tooltip: format!("Codex Quota · Antigravity\n{}", tooltip_lines.join("\n")),
        items,
    }
}

/// 写入单个状态项的菜单、提示与标题；Windows 托盘不支持标题，仅使用图标与提示。
fn apply_tray_content(app: &AppHandle, tray: &tauri::tray::TrayIcon, service: &str, content: TrayContent) {
    let mut countdowns = Vec::new();
    let menu = (|| -> tauri::Result<tauri::menu::Menu<tauri::Wry>> {
        use tauri::menu::{IconMenuItem, Menu, MenuItem, PredefinedMenuItem};
        let menu = Menu::new(app)?;
        menu.append(&MenuItem::new(app, format!("{service} 额度"), false, None::<&str>)?)?;

        for spec in &content.items {
            match spec {
                TrayMenuItemSpec::Quota { id, label, remaining_percent } => {
                    let icon = create_progress_capsule_icon(*remaining_percent);
                    let item = IconMenuItem::with_id(app, id, label, true, Some(icon), None::<&str>)?;
                    menu.append(&item)?;
                }
                TrayMenuItemSpec::ActionNote(text) => {
                    let item = MenuItem::with_id(app, "open", text, true, None::<&str>)?;
                    menu.append(&item)?;
                }
                TrayMenuItemSpec::Deadline { label, timestamp, expires } => {
                    let text = deadline_text(label, *timestamp, *expires, crate::state::now());
                    let item = MenuItem::with_id(app, "open", &text, true, None::<&str>)?;
                    menu.append(&item)?;
                    countdowns.push(TrayCountdown { item, label: label.clone(), timestamp: *timestamp, expires: *expires, text });
                }
                TrayMenuItemSpec::Info(text) => {
                    let item = MenuItem::new(app, text, false, None::<&str>)?;
                    menu.append(&item)?;
                }
            }
        }

        menu.append(&PredefinedMenuItem::separator(app)?)?;
        menu.append(&MenuItem::with_id(app, "open", "打开面板", true, Some("CmdOrCtrl+0"))?)?;
        menu.append(&MenuItem::with_id(app, "quit", "退出 Codex Quota", true, None::<&str>)?)?;
        Ok(menu)
    })();

    if let Ok(menu) = menu {
        if tray.set_menu(Some(menu)).is_ok() {
            app.state::<TrayCountdowns>().0.lock().unwrap().insert(service.into(), countdowns);
        }
    }
    let _ = tray.set_tooltip(Some(content.tooltip));
    #[cfg(target_os = "macos")]
    {
        let _ = tray.set_title(Some(content.title));
        let _ = tray.with_inner_tray_icon(|tray| {
            use objc2::MainThreadMarker;
            use objc2_app_kit::{NSFont, NSFontWeightRegular};

            let mtm = MainThreadMarker::new().expect("Tray updates run on the main thread");
            if let Some(button) = tray.ns_status_item().and_then(|item| item.button(mtm)) {
                let font = NSFont::monospacedDigitSystemFontOfSize_weight(
                    NSFont::menuBarFontOfSize(0.0).pointSize(),
                    unsafe { NSFontWeightRegular },
                );
                button.setFont(Some(&font));
                button.setImageHugsTitle(true);
            }
        });
    }
    #[cfg(not(target_os = "macos"))]
    let _ = content.title;
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
    app.manage(TrayCountdowns::default());
    let open = MenuItem::with_id(app, "open", "打开面板", true, Some("CmdOrCtrl+0"))?;
    let quit = MenuItem::with_id(app, "quit", "退出 Codex Quota", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open, &PredefinedMenuItem::separator(app)?, &quit])?;
    // macOS 后创建的状态项排在左侧：先建 Antigravity，使 Codex 默认位于其左边。
    for (id, bytes) in TRAY_ICONS {
        tauri::tray::TrayIconBuilder::with_id(id)
            .icon(tray_icon(bytes, false)?)
            .icon_as_template(cfg!(target_os = "macos"))
            .menu(&menu)
            .show_menu_on_left_click(true)
            .build(app)?;
    }
    #[cfg(windows)]
    taskbar_theme::sync(app);
    let settings = MenuItem::with_id(app, "settings", "设置…", true, Some("CmdOrCtrl+,"))?;
    let refresh = MenuItem::with_id(app, "refresh", "刷新用量", true, Some("CmdOrCtrl+R"))?;
    let main = Submenu::with_items(
        app,
        "Codex Quota",
        true,
        &[
            &settings,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::quit(app, Some("退出 Codex Quota"))?,
        ],
    )?;
    #[cfg(target_os = "macos")]
    main.insert_items(&[
        &PredefinedMenuItem::hide(app, Some("隐藏 Codex Quota"))?,
        &PredefinedMenuItem::hide_others(app, Some("隐藏其他"))?,
        &PredefinedMenuItem::show_all(app, Some("显示全部"))?,
        &PredefinedMenuItem::separator(app)?,
    ], 2)?;
    let edit = Submenu::with_items(
        app,
        "编辑",
        true,
        &[
            &PredefinedMenuItem::undo(app, None)?,
            &PredefinedMenuItem::redo(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, None)?,
            &PredefinedMenuItem::copy(app, None)?,
            &PredefinedMenuItem::paste(app, None)?,
            &PredefinedMenuItem::select_all(app, None)?,
        ],
    )?;
    let window = Submenu::with_items(
        app,
        "窗口",
        true,
        &[
            &open,
            &refresh,
            &PredefinedMenuItem::minimize(app, None)?,
            &PredefinedMenuItem::maximize(app, Some("缩放"))?,
            &PredefinedMenuItem::close_window(app, None)?,
        ],
    )?;
    #[cfg(target_os = "macos")]
    window.append_items(&[
        &PredefinedMenuItem::separator(app)?,
        &PredefinedMenuItem::bring_all_to_front(app, Some("前置全部窗口"))?,
    ])?;
    app.set_menu(Menu::with_items(app, &[&main, &edit, &window])?)?;
    #[cfg(windows)]
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.hide_menu();
    }
    app.on_menu_event(|app, event| match event.id.as_ref() {
        "settings" => {
            open_window(app);
            let _ = app.emit("navigate", "settings");
        }
        "refresh" => {
            let _ = app.emit("refresh-usage", ());
        }
        s if s.starts_with("open") => open_window(app),
        // 两个状态项菜单共用全局事件，避免各自注册导致重复处理。
        "quit" => app.exit(0),
        _ => {}
    });
    power::install(app);
    let countdown_app = app.clone();
    tauri::async_runtime::spawn(async move {
        let state = controller(&countdown_app);
        let mut interval = tokio::time::interval(Duration::from_secs(1));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            interval.tick().await;
            if state.paused.load(std::sync::atomic::Ordering::Relaxed) {
                continue;
            }
            let app = countdown_app.clone();
            let _ = countdown_app.run_on_main_thread(move || {
                let time = crate::state::now();
                for countdown in app.state::<TrayCountdowns>().0.lock().unwrap().values_mut().flatten() {
                    let text = deadline_text(&countdown.label, countdown.timestamp, countdown.expires, time);
                    if text != countdown.text && countdown.item.set_text(&text).is_ok() {
                        countdown.text = text;
                    }
                }
            });
        }
    });
    #[cfg(target_os = "macos")]
    if let Some(window) = app.get_webview_window("main") {
        update_app_icon(app, window.theme()?);
    }
    Ok(())
}

#[cfg(target_os = "macos")]
pub fn update_app_icon(app: &AppHandle, theme: tauri::Theme) {
    use objc2::{AnyThread, MainThreadMarker};
    use objc2_app_kit::{NSApplication, NSImage};
    use objc2_foundation::NSData;

    let _ = app.run_on_main_thread(move || {
        let mtm = MainThreadMarker::new().expect("Dock icon updates run on the main thread");
        let bytes: &[u8] = if theme == tauri::Theme::Dark {
            include_bytes!("../icons/dock-dark.png")
        } else {
            include_bytes!("../icons/icon.icns")
        };
        let data = NSData::with_bytes(bytes);
        if let Some(image) = NSImage::initWithData(NSImage::alloc(), &data) {
            // AppKit requires a non-null image; both variants are bundled assets.
            unsafe { NSApplication::sharedApplication(mtm).setApplicationIconImage(Some(&image)) };
        }
    });
}

pub fn open_external(app: &AppHandle, value: &str) -> Result<(), String> {
    let url = url::Url::parse(value).map_err(|_| "链接格式无效")?;
    let allowed = url.scheme() == "https"
        && (url.host_str() == Some("github.com") && url.path().starts_with("/sunpm/codex-quota/")
            || url.host_str() == Some("x.com")
                && url
                    .path()
                    .strip_prefix("/thsottiaux/status/").or_else(|| url.path().strip_prefix("/_mohansolo/status/"))
                    .is_some_and(|v| !v.is_empty() && v.bytes().all(|c| c.is_ascii_digit()))
            || url.host_str() == Some("aihot.news")
                && ["/codex-reset", "/antigravity-reset", "/terms"].contains(&url.path())
            || [("developers.openai.com", "/api/docs/pricing"), ("ai.google.dev", "/gemini-api/docs/pricing"), ("platform.claude.com", "/docs/en/about-claude/pricing")]
                .iter().any(|(host, path)| url.host_str() == Some(host) && url.path() == *path));
    if !allowed {
        return Err("此链接不属于应用的数据来源。".into());
    }
    app.opener()
        .open_url(value, None::<&str>)
        .map_err(|_| "无法打开链接，请检查默认浏览器。".into())
}

pub fn open_notification_settings(app: &AppHandle) -> Result<(), String> {
    let target = if cfg!(target_os = "macos") {
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
    } else {
        "ms-settings:notifications"
    };
    app.opener()
        .open_url(target, None::<&str>)
        .map_err(|_| "无法打开系统通知设置。".into())
}

#[cfg(target_os = "macos")]
pub fn autostart_enabled(_app: &AppHandle) -> bool {
    use objc2_service_management::{SMAppService, SMAppServiceStatus};
    unsafe { SMAppService::mainAppService().status() == SMAppServiceStatus::Enabled }
}
#[cfg(not(target_os = "macos"))]
pub fn autostart_enabled(app: &AppHandle) -> bool {
    use tauri_plugin_autostart::ManagerExt;
    app.autolaunch().is_enabled().unwrap_or(false)
}

#[cfg(target_os = "macos")]
pub fn set_autostart(_app: &AppHandle, enabled: bool) -> Result<(), String> {
    use objc2_service_management::{SMAppService, SMAppServiceStatus};
    unsafe {
        let service = SMAppService::mainAppService();
        if enabled {
            service.registerAndReturnError()
        } else {
            service.unregisterAndReturnError()
        }
        .map_err(|_| "设置登录启动失败，请将应用移入“应用程序”后重试。")?;
        if service.status() == SMAppServiceStatus::RequiresApproval {
            return Err("请在系统设置 → 通用 → 登录项中允许此应用。".into());
        }
    }
    Ok(())
}
#[cfg(not(target_os = "macos"))]
pub fn set_autostart(app: &AppHandle, enabled: bool) -> Result<(), String> {
    use tauri_plugin_autostart::ManagerExt;
    if enabled {
        app.autolaunch().enable()
    } else {
        app.autolaunch().disable()
    }
    .map_err(|_| "设置登录启动失败，请检查系统权限。".into())
}

#[derive(serde::Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum NotificationPermission {
    Granted,
    Denied,
    Prompt,
    System,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum NotificationAlertStyle {
    Persistent,
    Banner,
    Disabled,
    Unknown,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NotificationStatus {
    pub permission: NotificationPermission,
    pub alert_style: NotificationAlertStyle,
}

#[cfg(target_os = "macos")]
pub async fn notification_permission(request: bool) -> Result<NotificationStatus, String> {
    use block2::RcBlock;
    use objc2::runtime::Bool;
    use objc2_foundation::NSError;
    use objc2_user_notifications::{
        UNAlertStyle, UNAuthorizationOptions, UNAuthorizationStatus, UNNotificationSetting,
        UNNotificationSettings, UNUserNotificationCenter,
    };
    use std::sync::Mutex;
    if !crate::notifications::is_bundled() {
        return Ok(NotificationStatus {
            permission: NotificationPermission::System,
            alert_style: NotificationAlertStyle::Unknown,
        });
    }
    if request {
        let (sender, receiver) = tokio::sync::oneshot::channel();
        {
            let sender = Mutex::new(Some(sender));
            let block = RcBlock::new(move |_granted: Bool, error: *mut NSError| {
                if let Some(sender) = sender.lock().unwrap().take() {
                    let _ = sender.send(if error.is_null() {
                        Ok(())
                    } else {
                        Err("无法申请通知权限。".to_string())
                    });
                }
            });
            UNUserNotificationCenter::currentNotificationCenter()
                .requestAuthorizationWithOptions_completionHandler(
                    UNAuthorizationOptions::Alert | UNAuthorizationOptions::Sound,
                    &block,
                );
        }
        receiver
            .await
            .map_err(|_| "无法申请通知权限。".to_string())??;
    }
    let (sender, receiver) = tokio::sync::oneshot::channel();
    {
        let sender = Mutex::new(Some(sender));
        let block = RcBlock::new(move |settings: std::ptr::NonNull<UNNotificationSettings>| {
            let settings = unsafe { settings.as_ref() };
            let status = settings.authorizationStatus();
            let status = if status == UNAuthorizationStatus::Authorized
                || status == UNAuthorizationStatus::Provisional
            {
                NotificationPermission::Granted
            } else if status == UNAuthorizationStatus::Denied {
                NotificationPermission::Denied
            } else {
                NotificationPermission::Prompt
            };
            if let Some(sender) = sender.lock().unwrap().take() {
                let alert_style = if status != NotificationPermission::Granted {
                    NotificationAlertStyle::Unknown
                } else if settings.alertSetting() == UNNotificationSetting::Disabled {
                    NotificationAlertStyle::Disabled
                } else if settings.alertSetting() != UNNotificationSetting::Enabled {
                    NotificationAlertStyle::Unknown
                } else if settings.alertStyle() == UNAlertStyle::Alert {
                    NotificationAlertStyle::Persistent
                } else if settings.alertStyle() == UNAlertStyle::Banner {
                    NotificationAlertStyle::Banner
                } else if settings.alertStyle() == UNAlertStyle::None {
                    NotificationAlertStyle::Disabled
                } else {
                    NotificationAlertStyle::Unknown
                };
                let _ = sender.send(NotificationStatus {
                    alert_style,
                    permission: status,
                });
            }
        });
        UNUserNotificationCenter::currentNotificationCenter()
            .getNotificationSettingsWithCompletionHandler(&block);
    }
    receiver.await.map_err(|_| "无法读取通知权限。".to_string())
}
#[cfg(not(target_os = "macos"))]
pub async fn notification_permission(_request: bool) -> Result<NotificationStatus, String> {
    Ok(NotificationStatus {
        permission: NotificationPermission::System,
        alert_style: NotificationAlertStyle::Unknown,
    })
}

#[cfg(target_os = "macos")]
pub mod power {
    use super::*;
    use objc2::{rc::Retained, runtime::ProtocolObject};
    use objc2_foundation::NSObjectProtocol;
    use std::cell::RefCell;
    thread_local! {static OBSERVERS:RefCell<Vec<Retained<ProtocolObject<dyn NSObjectProtocol>>>>=const{RefCell::new(Vec::new())};}
    pub fn install(app: &AppHandle) {
        use objc2_app_kit::{
            NSWorkspace, NSWorkspaceDidWakeNotification, NSWorkspaceWillSleepNotification,
        };
        let center = NSWorkspace::sharedWorkspace().notificationCenter();
        for (name, paused) in unsafe {
            [
                (NSWorkspaceWillSleepNotification, true),
                (NSWorkspaceDidWakeNotification, false),
            ]
        } {
            let app = app.clone();
            let block = block2::RcBlock::new(
                move |_notification: std::ptr::NonNull<objc2_foundation::NSNotification>| {
                    controller(&app).set_paused(&app, paused);
                },
            );
            let observer = unsafe {
                center.addObserverForName_object_queue_usingBlock(Some(name), None, None, &block)
            };
            OBSERVERS.with(|observers| observers.borrow_mut().push(observer));
        }
    }
    pub fn cleanup() {
        let center = objc2_app_kit::NSWorkspace::sharedWorkspace().notificationCenter();
        OBSERVERS.with(|observers| {
            for observer in observers.borrow_mut().drain(..) {
                let object: &ProtocolObject<dyn NSObjectProtocol> = &observer;
                unsafe { center.removeObserver(object.as_ref()) };
            }
        });
    }
}

#[cfg(windows)]
pub mod power {
    use super::*;
    use std::{cell::RefCell, ffi::c_void};
    use windows_sys::Win32::{System::Power::*, UI::WindowsAndMessaging::DEVICE_NOTIFY_CALLBACK};
    thread_local! {static REGISTRATION:RefCell<Option<(HPOWERNOTIFY,*mut AppHandle)>>=const{RefCell::new(None)};}
    unsafe extern "system" fn changed(
        context: *const c_void,
        kind: u32,
        _setting: *const c_void,
    ) -> u32 {
        let app = unsafe { &*context.cast::<AppHandle>() };
        if kind == 4 {
            controller(app).set_paused(app, true);
        } else if kind == 18 || kind == 7 {
            controller(app).set_paused(app, false);
        }
        0
    }
    pub fn install(app: &AppHandle) {
        let context = Box::into_raw(Box::new(app.clone()));
        let params = DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS {
            Callback: Some(changed),
            Context: context.cast(),
        };
        let mut handle = std::ptr::null_mut();
        let result = unsafe {
            PowerRegisterSuspendResumeNotification(
                DEVICE_NOTIFY_CALLBACK,
                (&params as *const DEVICE_NOTIFY_SUBSCRIBE_PARAMETERS)
                    .cast_mut()
                    .cast(),
                &mut handle,
            )
        };
        if result == 0 {
            // windows-sys returns a pointer here, but unregister accepts HPOWERNOTIFY.
            REGISTRATION.with(|r| *r.borrow_mut() = Some((handle as HPOWERNOTIFY, context)));
        } else {
            unsafe { drop(Box::from_raw(context)) };
            controller(app).store.lock().unwrap().snapshot.error =
                Some("无法监听系统睡眠状态。".into());
        }
    }
    pub fn cleanup() {
        REGISTRATION.with(|r| {
            if let Some((handle, context)) = r.borrow_mut().take() {
                unsafe {
                    PowerUnregisterSuspendResumeNotification(handle);
                    drop(Box::from_raw(context));
                }
            }
        });
    }
}

#[cfg(not(any(target_os = "macos", windows)))]
pub mod power {
    use super::*;
    pub fn install(_app: &AppHandle) {}
    pub fn cleanup() {}
}

pub async fn send_notification(
    app: &AppHandle,
    title: &str,
    body: &str,
    source_url: Option<&str>,
) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        let _ = app;
        crate::notifications::send(title, body, source_url).await
    }
    #[cfg(not(target_os = "macos"))]
    {
        use tauri_plugin_notification::NotificationExt;
        let mut notification = app.notification().builder().title(title).body(body);
        if let Some(url) = source_url {
            notification = notification.extra("sourceUrl", url);
        }
        notification
            .show()
            .map_err(|_| "通知发送失败，请检查系统通知设置。".into())
    }
}
