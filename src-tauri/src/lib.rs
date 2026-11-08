mod antigravity;
mod client;
mod monitor;
#[cfg(target_os = "macos")]
mod notifications;
mod platform;
mod state;
mod updates;

use monitor::{controller, Controller};
use state::{AppSnapshot, Settings};
use std::sync::{atomic::Ordering, Arc};
use tauri::{AppHandle, Manager};
#[cfg(not(target_os = "macos"))]
use tauri_plugin_notification::NotificationExt;

#[tauri::command]
fn get_snapshot(app: AppHandle) -> AppSnapshot {
    controller(&app).store.lock().unwrap().snapshot.clone()
}

#[tauri::command]
async fn refresh_quota(app: AppHandle) -> AppSnapshot {
    tokio::join!(
        monitor::refresh_quota(&app, true),
        monitor::refresh_announcements(&app),
        monitor::refresh_antigravity(&app, false),
        monitor::refresh_antigravity_announcements(&app)
    );
    get_snapshot(app)
}

#[tauri::command]
async fn refresh_antigravity(app: AppHandle) -> AppSnapshot {
    monitor::refresh_antigravity(&app, true).await;
    get_snapshot(app)
}

#[tauri::command]
async fn scan_usage(app: AppHandle, rescan: bool) -> AppSnapshot {
    monitor::scan_usage(&app, rescan).await;
    get_snapshot(app)
}

#[tauri::command]
async fn save_settings(app: AppHandle, settings: Settings) -> Result<AppSnapshot, String> {
    settings.validate()?;
    let state = controller(&app);
    let previous = state.store.lock().unwrap().snapshot.settings.clone();
    if previous.launch_at_login != settings.launch_at_login {
        platform::set_autostart(&app, settings.launch_at_login)?;
    }
    let saved_result = {
        let mut store = state.store.lock().unwrap();
        let mut saved = store.saved.clone();
        settings.save_into(&mut saved.preferences);
        if settings.monitoring_enabled != previous.monitoring_enabled {
            saved.recovery.state = None;
            saved.announcements.tracker.has_baseline = false;
            if settings.monitoring_enabled {
                saved.schedule.next_attempt = 0.0;
            }
        }
        if settings.antigravity_enabled != previous.antigravity_enabled {
            saved.antigravity_announcements.tracker.has_baseline = false;
            if settings.antigravity_enabled { saved.antigravity_schedule.next_attempt = 0.0; }
        }
        if settings.refresh_interval != previous.refresh_interval && saved.antigravity_schedule.failures == 0 {
            saved.antigravity_schedule.next_attempt = state::now() + settings.refresh_interval as f64;
        }
        if settings.refresh_interval != previous.refresh_interval && saved.schedule.failures == 0 {
            saved.schedule.next_attempt = state::now() + settings.refresh_interval as f64;
        }
        if settings.automatic_updates && !previous.automatic_updates {
            saved.next_update_check = 0.0;
        }
        store.commit(saved)
    };
    if let Err(error) = saved_result {
        if previous.launch_at_login != settings.launch_at_login {
            let _ = platform::set_autostart(&app, previous.launch_at_login);
        }
        state.emit(&app);
        return Err(error);
    }
    {
        let mut store = state.store.lock().unwrap();
        store.snapshot.settings = settings.clone();
        if settings.antigravity_enabled != previous.antigravity_enabled {
            store.snapshot.antigravity.requires_action = false;
            if !settings.antigravity_enabled { store.snapshot.antigravity.refreshing = false; store.snapshot.antigravity_announcements.refreshing = false; }
        }
        if settings.monitoring_enabled != previous.monitoring_enabled {
            store.continuous = false;
        }
    }
    let active =
        settings.monitoring_enabled && !state.paused.load(Ordering::Relaxed) && !state.preview;
    if *state.active.borrow() != active {
        state.active.send_replace(active);
    }
    if !active {
        state.client.lock().await.stop().await;
    }
    let antigravity_active = settings.antigravity_enabled && !state.paused.load(Ordering::Relaxed) && !state.preview;
    if *state.antigravity_active.borrow() != antigravity_active { state.antigravity_active.send_replace(antigravity_active); }
    if !antigravity_active { state.antigravity_client.lock().await.stop().await; }
    if settings.antigravity_enabled && !previous.antigravity_enabled {
        let handle = app.clone();
        tauri::async_runtime::spawn(async move { tokio::join!(monitor::refresh_antigravity(&handle, true), monitor::refresh_antigravity_announcements(&handle)); });
    }
    if !settings.automatic_updates {
        updates::cancel_check(&app);
    }
    state.emit(&app);
    if settings.monitoring_enabled && !previous.monitoring_enabled {
        let handle = app.clone();
        tauri::async_runtime::spawn(async move {
            monitor::refresh_quota(&handle, true).await;
        });
    }
    Ok(get_snapshot(app))
}

#[tauri::command]
fn save_prices(
    app: AppHandle,
    prices: Vec<quota_core::ModelPricing>,
) -> Result<AppSnapshot, String> {
    if prices
        .iter()
        .any(|price| price.service != "codex" || !price.is_valid())
    {
        return Err("模型价格无效，请检查名称、非负单价、倍率和上下文阈值。".into());
    }
    let state = controller(&app);
    {
        let mut store = state.store.lock().unwrap();
        let mut saved = store.saved.clone();
        for price in prices {
            saved
                .overrides
                .insert(format!("codex:{}", price.model.to_lowercase()), price);
        }
        store.commit(saved)?;
        store.reprice();
    }
    state.emit(&app);
    Ok(get_snapshot(app))
}

#[tauri::command]
fn reset_price(app: AppHandle, model: String) -> Result<AppSnapshot, String> {
    let state = controller(&app);
    {
        let mut store = state.store.lock().unwrap();
        let mut saved = store.saved.clone();
        saved
            .overrides
            .remove(&format!("codex:{}", model.to_lowercase()));
        store.commit(saved)?;
        store.reprice();
    }
    state.emit(&app);
    Ok(get_snapshot(app))
}

#[tauri::command]
async fn update_prices(app: AppHandle) -> Result<AppSnapshot, String> {
    let state = controller(&app);
    {
        let mut store = state.store.lock().unwrap();
        if store.updating_prices {
            return Ok(store.snapshot.clone());
        }
        store.updating_prices = true;
    }
    let result = async {
        let response = state
            .http
            .get("https://models.dev/api.json")
            .send()
            .await
            .map_err(|_| "无法下载公开价格，请检查网络。")?
            .error_for_status()
            .map_err(|_| "公开价格服务暂不可用。")?;
        let bytes = response.bytes().await.map_err(|_| "公开价格下载未完成。")?;
        let catalog = quota_core::decode_catalog(&bytes)?;
        let mut store = state.store.lock().unwrap();
        let mut saved = store.saved.clone();
        saved.catalog = catalog;
        saved.price_date = chrono::Local::now().format("%Y-%m-%d").to_string();
        store.commit(saved)?;
        store.reprice();
        Ok::<(), String>(())
    }
    .await;
    state.store.lock().unwrap().updating_prices = false;
    state.emit(&app);
    result?;
    Ok(get_snapshot(app))
}

#[tauri::command]
async fn clear_history(app: AppHandle) -> Result<AppSnapshot, String> {
    let state = controller(&app);
    let reader = state.reader.clone();
    tauri::async_runtime::spawn_blocking(move || reader.lock().unwrap().clear_history())
        .await
        .map_err(|_| "清除历史未完成。")??;
    {
        let mut store = state.store.lock().unwrap();
        store.snapshot.usage.records.clear();
        store.snapshot.usage.scanned_at = None;
        store.reprice();
    }
    state.emit(&app);
    monitor::scan_usage(&app, true).await;
    Ok(get_snapshot(app))
}

#[tauri::command]
async fn notification_permission() -> Result<platform::NotificationStatus, String> {
    platform::notification_permission(false).await
}
#[tauri::command]
async fn request_notification_permission() -> Result<platform::NotificationStatus, String> {
    platform::notification_permission(true).await
}
#[tauri::command]
fn mark_notification_guide_shown(app: AppHandle) -> Result<AppSnapshot, String> {
    let state = controller(&app);
    {
        let mut store = state.store.lock().unwrap();
        let mut saved = store.saved.clone();
        saved.preferences.insert(
            "notifications.persistentGuideShown".into(),
            serde_json::json!(true),
        );
        store.commit(saved)?;
        store.snapshot.notification_guide_shown = true;
    }
    state.emit(&app);
    Ok(get_snapshot(app))
}
#[tauri::command]
async fn test_notification(app: AppHandle) -> Result<(), String> {
    let settings = controller(&app)
        .store
        .lock()
        .unwrap()
        .snapshot
        .settings
        .clone();
    if !(settings.monitoring_enabled
        && (settings.recovery_notifications
            || settings.reset_credit_reminders
            || settings.quota_reset_reminders
            || settings.announcement_notifications)
        || settings.antigravity_enabled && settings.antigravity_announcement_notifications)
    {
        return Err("请先开启额度监测和至少一种通知。".into());
    }
    if !matches!(
        platform::notification_permission(false).await?.permission,
        platform::NotificationPermission::Granted | platform::NotificationPermission::System
    ) {
        return Err("通知未获允许，请在系统设置中开启。".into());
    }
    platform::send_notification(
        &app,
        "Codex 通知测试",
        "通知已就绪，将按设置发送额度恢复、重置前、重置卡到期或重置动态提醒。",
        None,
    )
    .await
}
#[tauri::command]
fn open_notification_settings(app: AppHandle) -> Result<(), String> {
    platform::open_notification_settings(&app)
}
#[tauri::command]
fn open_external(app: AppHandle, url: String) -> Result<(), String> {
    platform::open_external(&app, &url)
}
#[tauri::command]
async fn check_update(app: AppHandle) -> Result<AppSnapshot, String> {
    updates::check(&app).await
}
#[tauri::command]
async fn install_update(app: AppHandle) -> Result<AppSnapshot, String> {
    updates::install(&app).await
}
#[tauri::command]
fn cancel_update(app: AppHandle) -> AppSnapshot {
    updates::cancel(&app)
}
#[tauri::command]
fn quit_app(app: AppHandle) {
    app.exit(0);
}

pub fn run() {
    let window_state_directory = std::env::var_os("CODEX_QUOTA_DATA_DIR")
        .map(std::path::PathBuf::from)
        .or_else(|| dirs::data_dir().map(|path| path.join("CodexQuotaDock")))
        .expect("无法找到应用数据目录");
    let window_state_path = std::path::absolute(window_state_directory.join("window-state.json"))
        .expect("无法解析窗口状态保存路径");
    let window_state_flags = tauri_plugin_window_state::StateFlags::SIZE
        | tauri_plugin_window_state::StateFlags::POSITION
        | tauri_plugin_window_state::StateFlags::MAXIMIZED;
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            platform::open_window(app)
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::Builder::new().build())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_window_state::Builder::new()
            .with_filename(window_state_path.to_string_lossy())
            .with_state_flags(window_state_flags)
            .build())
        .invoke_handler(tauri::generate_handler![
            get_snapshot,
            refresh_quota,
            refresh_antigravity,
            scan_usage,
            save_settings,
            save_prices,
            reset_price,
            update_prices,
            clear_history,
            notification_permission,
            request_notification_permission,
            mark_notification_guide_shown,
            test_notification,
            open_notification_settings,
            open_external,
            check_update,
            install_update,
            cancel_update,
            updates::mark_release_notes_shown,
            quit_app
        ])
        .setup(move |app| {
            let state = Arc::new(Controller::new(app.handle()).map_err(std::io::Error::other)?);
            // The plugin creates its default config directory, not a custom file's parent.
            if std::fs::create_dir_all(&window_state_directory).is_err() {
                state.store.lock().unwrap().snapshot.error
                    .get_or_insert_with(|| "无法创建窗口状态保存目录。".into());
            }
            state
                .store
                .lock()
                .unwrap()
                .snapshot
                .settings
                .launch_at_login = platform::autostart_enabled(app.handle());
            app.manage(state.clone());
            platform::setup(app.handle())?;
            #[cfg(target_os = "macos")]
            notifications::setup(app.handle());
            #[cfg(not(target_os = "macos"))]
            {
                let handle = app.handle().clone();
                app.notification().on_action(move |action| {
                    if action.action_id() == "dismiss" {
                        return;
                    }
                    if let Some(url) = action
                        .notification()
                        .and_then(|v| v.extra().get("sourceUrl"))
                        .and_then(serde_json::Value::as_str)
                    {
                        let _ = platform::open_external(&handle, url);
                    } else {
                        platform::open_window(&handle);
                    }
                })?;
            }
            if state.preview {
                if let Some(window) = app.get_webview_window("main") {
                    window.set_title("Codex Quota · 离线验收")?;
                }
            }
            state.emit(app.handle());
            platform::open_window(app.handle());
            monitor::start(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| {
            #[cfg(target_os = "macos")]
            if let tauri::WindowEvent::ThemeChanged(theme) = event {
                platform::update_app_icon(window.app_handle(), *theme);
            }
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let app = window.app_handle();
                let snapshot = controller(app).store.lock().unwrap().snapshot.clone();
                let has_tray = snapshot.settings.show_tray && snapshot.settings.monitoring_enabled
                    || snapshot.settings.antigravity_show_tray && snapshot.settings.antigravity_enabled;
                #[cfg(windows)]
                if !has_tray {
                    let _ = window.minimize();
                    return;
                }
                let _ = window.hide();
                #[cfg(target_os = "macos")]
                let _ = app.set_activation_policy(if has_tray {
                    tauri::ActivationPolicy::Accessory
                } else {
                    tauri::ActivationPolicy::Regular
                });
            }
        })
        .build(tauri::generate_context!())
        .expect("无法启动 Codex Quota")
        .run(|app, event| match event {
            #[cfg(target_os = "macos")]
            tauri::RunEvent::Reopen { .. } => platform::open_window(app),
            tauri::RunEvent::Exit => {
                platform::power::cleanup();
                let state = controller(app);
                state.active.send_replace(false);
                state.antigravity_active.send_replace(false);
                updates::cancel_check(app);
                if let Some(task) = state.updates.lock().unwrap().downloading.take() {
                    task.abort();
                }
                tauri::async_runtime::block_on(async {
                    tokio::join!(async { state.client.lock().await.stop().await }, async { state.antigravity_client.lock().await.stop().await });
                });
            }
            _ => {}
        });
}
