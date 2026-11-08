use crate::{monitor::controller, state::AppSnapshot};
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

pub fn update_tray(app: &AppHandle, snapshot: &AppSnapshot) {
    if let Some(tray) = app.tray_by_id("quota") {
        let codex_visible = snapshot.settings.show_tray && snapshot.settings.monitoring_enabled;
        let antigravity_visible = snapshot.settings.antigravity_show_tray && snapshot.settings.antigravity_enabled;
        let visible = codex_visible || antigravity_visible;
        let _ = tray.set_visible(visible);
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
        let mut description = snapshot.quota.windows.iter().map(|window| {
            let name = if window.bucket == "codex" {
                window.display_label()
            } else {
                format!("{} · {}", window.name, window.display_label())
            };
            let reset = window.resets_at
                .and_then(|timestamp| chrono::DateTime::from_timestamp(timestamp as i64, 0))
                .map(|date| format!("，{} 重置", date.with_timezone(&chrono::Local).format("%m-%d %H:%M")))
                .unwrap_or_default();
            format!("{name}：剩余 {}%{reset}", window.remaining().floor() as u64)
        }).collect::<Vec<_>>();
        if description.is_empty() {
            description.push("等待额度数据".into());
        }
        if let Some(error) = &snapshot.quota.error {
            description.push(format!("额度可能已过期：{error}"));
        }
        if codex_visible {
            description.insert(0, "Codex".into());
            if antigravity_visible { title = format!("C {title}"); }
        } else {
            description.clear();
            title.clear();
        }
        if antigravity_visible {
            let quota = &snapshot.antigravity;
            let buckets: Vec<_> = quota.groups.iter().flat_map(|group| &group.buckets).filter(|bucket| !bucket.disabled).collect();
            let minimum = buckets.iter().filter_map(|bucket| bucket.remaining_percent).reduce(f64::min);
            let value = minimum.map(|value| format!("{}%", value.floor() as u64)).unwrap_or_else(|| "--".into());
            let status = if quota.error.is_some() { " !" } else if quota.refreshing { " …" } else if buckets.iter().any(|bucket| bucket.remaining_percent.is_none()) { " ?" } else { "" };
            if !title.is_empty() { title.push_str(" | "); }
            title.push_str(&format!("AG {value}{status}"));
            description.push(format!("Antigravity · 最低已知剩余 {value}{status}"));
            for group in &quota.groups {
                for bucket in &group.buckets {
                    let window = match bucket.window.as_deref() { Some("5h") => "五小时额度", Some("weekly") => "周额度", _ => "额度" };
                    let remaining = if bucket.disabled { "未启用".into() } else { bucket.remaining_percent.map(|value| format!("剩余 {}%", value.floor() as u64)).unwrap_or_else(|| "剩余额度未知".into()) };
                    let reset = bucket.resets_at.and_then(|timestamp| chrono::DateTime::from_timestamp(timestamp as i64, 0))
                        .map(|date| format!("{} 重置", date.with_timezone(&chrono::Local).format("%m-%d %H:%M")))
                        .unwrap_or_else(|| "重置时间未知".into());
                    description.push(format!("{} · {window} · {} [{}]：{remaining}，{reset}", group.name, bucket.name, bucket.id));
                }
            }
            if let Some(error) = &quota.error { description.push(format!("Antigravity：{error}")); }
            if let Some(time) = quota.last_success.and_then(|timestamp| chrono::DateTime::from_timestamp(timestamp as i64, 0)) {
                description.push(format!("Antigravity 上次读取{}：{}", if quota.error.is_some() { "（已过期）" } else { "" }, time.with_timezone(&chrono::Local).format("%m-%d %H:%M")));
            }
        }
        // Windows tooltips are length-limited; the menu retains every returned bucket.
        let menu = (|| -> tauri::Result<tauri::menu::Menu<tauri::Wry>> {
            use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
            let menu = Menu::new(app)?;
            for line in &description { menu.append(&MenuItem::new(app, line, false, None::<&str>)?)?; }
            menu.append(&PredefinedMenuItem::separator(app)?)?;
            menu.append(&MenuItem::with_id(app, "open", "打开面板", true, Some("CmdOrCtrl+0"))?)?;
            menu.append(&MenuItem::with_id(app, "quit", "退出 Codex Quota", true, None::<&str>)?)?;
            Ok(menu)
        })();
        if let Ok(menu) = menu { let _ = tray.set_menu(Some(menu)); }
        let _ = tray.set_tooltip(Some(format!("Codex Quota\n{}", description.join("\n"))));
        #[cfg(target_os = "macos")]
        {
            let _ = tray.set_title(Some(title));
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
            let hidden = app
                .get_webview_window("main")
                .is_some_and(|w| !w.is_visible().unwrap_or(true));
            if hidden {
                let _ = app.set_activation_policy(if visible {
                    tauri::ActivationPolicy::Accessory
                } else {
                    tauri::ActivationPolicy::Regular
                });
            }
        }
    }
}

pub fn setup(app: &AppHandle) -> tauri::Result<()> {
    use tauri::menu::{Menu, MenuItem, PredefinedMenuItem, Submenu};
    let open = MenuItem::with_id(app, "open", "打开面板", true, Some("CmdOrCtrl+0"))?;
    let quit = MenuItem::with_id(app, "quit", "退出 Codex Quota", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open, &PredefinedMenuItem::separator(app)?, &quit])?;
    tauri::tray::TrayIconBuilder::with_id("quota")
        .icon(tauri::image::Image::from_bytes(include_bytes!(
            "../icons/tray.png"
        ))?)
        .icon_as_template(cfg!(target_os = "macos"))
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id.as_ref() {
            "open" => open_window(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
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
        "open" => open_window(app),
        _ => {}
    });
    power::install(app);
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
                && ["/codex-reset", "/antigravity-reset", "/terms"].contains(&url.path()));
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
