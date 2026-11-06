use block2::{DynBlock, RcBlock};
use objc2::{
    define_class, msg_send, rc::Retained, runtime::ProtocolObject, AnyThread, DefinedClass,
};
use objc2_foundation::{
    ns_string, NSDictionary, NSError, NSObject, NSObjectProtocol, NSString, NSUUID,
};
use objc2_user_notifications::{
    UNMutableNotificationContent, UNNotification, UNNotificationDefaultActionIdentifier,
    UNNotificationPresentationOptions, UNNotificationRequest, UNNotificationResponse,
    UNNotificationSound, UNUserNotificationCenter, UNUserNotificationCenterDelegate,
};
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

pub fn is_bundled() -> bool {
    std::env::current_exe().is_ok_and(|p| p.to_string_lossy().contains(".app/Contents/MacOS/"))
}

define_class!(
    #[unsafe(super(NSObject))]
    #[ivars = AppHandle]
    struct NotificationDelegate;

    unsafe impl NSObjectProtocol for NotificationDelegate {}

    unsafe impl UNUserNotificationCenterDelegate for NotificationDelegate {
        #[unsafe(method(userNotificationCenter:willPresentNotification:withCompletionHandler:))]
        fn will_present(
            &self,
            _center: &UNUserNotificationCenter,
            _notification: &UNNotification,
            completion: &DynBlock<dyn Fn(UNNotificationPresentationOptions)>,
        ) {
            completion.call((UNNotificationPresentationOptions::Banner
                | UNNotificationPresentationOptions::List
                | UNNotificationPresentationOptions::Sound,));
        }

        #[unsafe(method(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:))]
        fn did_receive(
            &self,
            _center: &UNUserNotificationCenter,
            response: &UNNotificationResponse,
            completion: &DynBlock<dyn Fn()>,
        ) {
            if &*response.actionIdentifier() == unsafe { UNNotificationDefaultActionIdentifier } {
                let info = response.notification().request().content().userInfo();
                let url = info
                    .objectForKey(ns_string!("sourceUrl"))
                    .and_then(|value| value.downcast::<NSString>().ok())
                    .map(|value| value.to_string());
                let app = self.ivars().clone();
                let _ = self.ivars().run_on_main_thread(move || {
                    if let Some(url) = url {
                        let _ = crate::platform::open_external(&app, &url);
                    } else {
                        crate::platform::open_window(&app);
                    }
                });
            }
            completion.call(());
        }
    }
);

// The delegate only holds a thread-safe AppHandle; UI work is dispatched to the main thread.
unsafe impl Send for NotificationDelegate {}
unsafe impl Sync for NotificationDelegate {}

pub fn setup(app: &AppHandle) {
    if !is_bundled() {
        return;
    }
    let delegate: Retained<NotificationDelegate> = unsafe {
        msg_send![
            super(NotificationDelegate::alloc().set_ivars(app.clone())),
            init
        ]
    };
    UNUserNotificationCenter::currentNotificationCenter()
        .setDelegate(Some(ProtocolObject::from_ref(&*delegate)));
    // The notification center's delegate property is weak.
    app.manage(delegate);
}

pub async fn send(title: &str, body: &str, source_url: Option<&str>) -> Result<(), String> {
    if !is_bundled() {
        return Err("请在打包后的应用中测试系统通知。".into());
    }
    let (sender, receiver) = tokio::sync::oneshot::channel();
    {
        let content = UNMutableNotificationContent::new();
        content.setTitle(&NSString::from_str(title));
        content.setBody(&NSString::from_str(body));
        content.setSound(Some(&UNNotificationSound::defaultSound()));
        if let Some(url) = source_url {
            let info =
                NSDictionary::from_slices(&[ns_string!("sourceUrl")], &[&*NSString::from_str(url)]);
            unsafe { content.setUserInfo(&info.cast_unchecked()) };
        }
        let request = UNNotificationRequest::requestWithIdentifier_content_trigger(
            &NSUUID::new().UUIDString(),
            &content,
            None,
        );
        let sender = Mutex::new(Some(sender));
        let completion = RcBlock::new(move |error: *mut NSError| {
            if let Some(sender) = sender.lock().unwrap().take() {
                let result = if error.is_null() {
                    Ok(())
                } else {
                    Err(format!(
                        "通知发送失败：{}",
                        unsafe { &*error }.localizedDescription()
                    ))
                };
                let _ = sender.send(result);
            }
        });
        UNUserNotificationCenter::currentNotificationCenter()
            .addNotificationRequest_withCompletionHandler(&request, Some(&completion));
    }
    receiver.await.map_err(|_| "通知发送未完成。".to_string())?
}
