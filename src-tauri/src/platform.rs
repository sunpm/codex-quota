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
        let visible = snapshot.settings.show_tray && snapshot.settings.monitoring_enabled;
        let _ = tray.set_visible(visible);
        let mut title = if snapshot.quota.windows.is_empty() {
            "--".into()
        } else {
            snapshot
                .quota
                .windows
                .iter()
                .take(2)
                .map(|window| format!("{}%", (100.0 - window.used_percent).floor() as u64))
                .collect::<Vec<_>>()
                .join(" ")
        };
        if snapshot.quota.error.is_some() {
            title.push_str(" !");
        }
        let _ = tray.set_tooltip(Some(format!("Codex Quota · {title}")));
        #[cfg(target_os = "macos")]
        {
            let _ = tray.set_title(Some(title));
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
    let open = MenuItem::with_id(app, "open", "打开面板", true, None::<&str>)?;
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
            &PredefinedMenuItem::close_window(app, None)?,
        ],
    )?;
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
    Ok(())
}

pub fn open_external(app: &AppHandle, value: &str) -> Result<(), String> {
    let url = url::Url::parse(value).map_err(|_| "链接格式无效")?;
    let allowed = url.scheme() == "https"
        && (url.host_str() == Some("github.com") && url.path().starts_with("/sunpm/codex-quota/")
            || url.host_str() == Some("x.com")
                && url
                    .path()
                    .strip_prefix("/thsottiaux/status/")
                    .is_some_and(|v| !v.is_empty() && v.bytes().all(|c| c.is_ascii_digit()))
            || url.host_str() == Some("aihot.news")
                && ["/codex-reset", "/terms"].contains(&url.path()));
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

#[cfg(target_os = "macos")]
pub async fn notification_permission(request: bool) -> Result<String, String> {
    use block2::RcBlock;
    use objc2::runtime::Bool;
    use objc2_foundation::NSError;
    use objc2_user_notifications::{
        UNAuthorizationOptions, UNAuthorizationStatus, UNNotificationSettings,
        UNUserNotificationCenter,
    };
    use std::sync::Mutex;
    // Apple's notification center requires an application bundle; cargo dev is an unbundled executable.
    if !std::env::current_exe().is_ok_and(|p| p.to_string_lossy().contains(".app/Contents/MacOS/"))
    {
        return Ok("system".into());
    }
    let (sender, receiver) = tokio::sync::oneshot::channel();
    let sender = Mutex::new(Some(sender));
    if request {
        let block = RcBlock::new(move |granted: Bool, error: *mut NSError| {
            if let Some(sender) = sender.lock().unwrap().take() {
                let _ = sender.send(if error.is_null() {
                    Ok(if granted.as_bool() {
                        "granted"
                    } else {
                        "denied"
                    }
                    .to_string())
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
    } else {
        let block = RcBlock::new(move |settings: std::ptr::NonNull<UNNotificationSettings>| {
            let status = unsafe { settings.as_ref() }.authorizationStatus();
            let status = if status == UNAuthorizationStatus::Authorized
                || status == UNAuthorizationStatus::Provisional
            {
                "granted"
            } else if status == UNAuthorizationStatus::Denied {
                "denied"
            } else {
                "prompt"
            };
            if let Some(sender) = sender.lock().unwrap().take() {
                let _ = sender.send(Ok(status.to_string()));
            }
        });
        UNUserNotificationCenter::currentNotificationCenter()
            .getNotificationSettingsWithCompletionHandler(&block);
    }
    receiver
        .await
        .map_err(|_| "无法读取通知权限。".to_string())?
}
#[cfg(not(target_os = "macos"))]
pub async fn notification_permission(_request: bool) -> Result<String, String> {
    Ok("system".into())
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
    thread_local! {static REGISTRATION:RefCell<Option<(*mut c_void,*mut AppHandle)>>=const{RefCell::new(None)};}
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
            REGISTRATION.with(|r| *r.borrow_mut() = Some((handle, context)));
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
