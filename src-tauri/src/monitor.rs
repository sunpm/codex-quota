use crate::{
    client::{fingerprint, CodexClient},
    state::*,
};
use quota_core::{LocalUsageReader, ResetAnnouncementFeed};
use std::{
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};
use tauri::{AppHandle, Emitter, Manager};
use tokio::sync::{watch, Mutex as AsyncMutex};

pub struct Controller {
    pub store: Mutex<Store>,
    pub reader: Arc<Mutex<LocalUsageReader>>,
    pub client: AsyncMutex<CodexClient>,
    pub antigravity_client: AsyncMutex<crate::antigravity::AntigravityClient>,
    pub http: reqwest::Client,
    pub active: watch::Sender<bool>,
    pub antigravity_active: watch::Sender<bool>,
    pub paused: AtomicBool,
    pub preview: bool,
    pub updates: Mutex<crate::updates::UpdateRuntime>,
}

pub fn controller(app: &AppHandle) -> Arc<Controller> {
    app.state::<Arc<Controller>>().inner().clone()
}

impl Controller {
    pub fn new(app: &AppHandle) -> Result<Self, String> {
        let preview = std::env::var_os("CODEX_QUOTA_PREVIEW").is_some();
        let data_dir = std::env::var_os("CODEX_QUOTA_DATA_DIR")
            .map(std::path::PathBuf::from)
            .or_else(|| dirs::data_dir().map(|p| p.join("CodexQuotaDock")))
            .ok_or("无法找到应用数据目录")?;
        let codex_home = std::env::var_os("CODEX_HOME")
            .filter(|v| !v.is_empty())
            .map(std::path::PathBuf::from)
            .or_else(|| dirs::home_dir().map(|p| p.join(".codex")))
            .ok_or("无法找到 Codex 目录")?;
        let path = data_dir.join("desktop-state.json");
        let (mut saved, error) = match SavedState::load(&path) {
            Ok(saved) => (saved, None),
            Err(error) => (SavedState::default(), Some(error)),
        };
        let mut settings = Settings::from_preferences(&saved.preferences);
        if preview || error.is_some() {
            settings.monitoring_enabled = false;
            settings.antigravity_enabled = false;
            settings.automatic_updates = false;
        }
        if !settings.monitoring_enabled {
            saved.recovery.state = None;
            saved.announcements.tracker.has_baseline = false;
        }
        if !settings.antigravity_enabled {
            saved.antigravity_announcements.tracker.has_baseline = false;
        }
        let snapshot = AppSnapshot {
            antigravity: AntigravitySnapshot::default(),
            antigravity_announcements: AnnouncementSnapshot {
                events: saved.antigravity_announcements.feed.as_ref().map(|feed| feed.events.clone()).unwrap_or_default(),
                source_status: saved.antigravity_announcements.feed.as_ref().and_then(|feed| feed.source_status(now())),
                ..Default::default()
            },
            quota: QuotaSnapshot {
                history: saved.quota_history.series.clone(),
                ..Default::default()
            },
            announcements: AnnouncementSnapshot {
                events: saved
                    .announcements
                    .feed
                    .as_ref()
                    .map(|v| v.events.clone())
                    .unwrap_or_default(),
                source_status: saved
                    .announcements
                    .feed
                    .as_ref()
                    .and_then(|v| v.source_status(now())),
                ..Default::default()
            },
            usage: UsageSnapshot {
                source: codex_home.to_string_lossy().into_owned(),
                ..Default::default()
            },
            prices: Vec::new(),
            price_date: saved.price_date.clone(),
            version: app.package_info().version.to_string(),
            platform: std::env::consts::OS.into(),
            update: UpdateState::default(),
            installed_release_notes: crate::updates::installed_release_notes(app, &saved),
            notification_guide_shown: saved
                .preferences
                .get("notifications.persistentGuideShown")
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false),
            error: error.clone(),
            settings: settings.clone(),
        };
        let mut store = Store {
            saved,
            snapshot,
            path,
            writable: error.is_none(),
            continuous: false,
            updating_prices: false,
        };
        store.reprice();
        let (active, _) = watch::channel(settings.monitoring_enabled && !preview);
        let (antigravity_active, _) = watch::channel(settings.antigravity_enabled && !preview);
        Ok(Self {
            store: Mutex::new(store),
            reader: Arc::new(Mutex::new(LocalUsageReader::new(
                codex_home,
                data_dir.join("usage-history.json"),
            ))),
            client: AsyncMutex::new(CodexClient::default()),
            antigravity_client: AsyncMutex::new(crate::antigravity::AntigravityClient::default()),
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(25))
                .user_agent("CodexQuota")
                .build()
                .map_err(|_| "无法初始化网络客户端")?,
            active,
            antigravity_active,
            paused: AtomicBool::new(false),
            preview,
            updates: Mutex::new(Default::default()),
        })
    }

    pub fn emit(&self, app: &AppHandle) {
        let snapshot = self.store.lock().unwrap().snapshot.clone();
        crate::platform::update_tray(app, &snapshot);
        let _ = app.emit("app-state", snapshot);
    }

    pub fn set_paused(&self, app: &AppHandle, paused: bool) {
        self.paused.store(paused, Ordering::Relaxed);
        let mut store = self.store.lock().unwrap();
        store.continuous = false;
        if !paused {
            store.saved.schedule.next_attempt = 0.0;
            store.saved.antigravity_schedule.next_attempt = 0.0;
        }
        self.active
            .send_replace(!paused && store.snapshot.settings.monitoring_enabled && !self.preview);
        self.antigravity_active.send_replace(!paused && store.snapshot.settings.antigravity_enabled && !self.preview);
        drop(store);
        if paused {
            crate::updates::cancel_check(app);
            let app = app.clone();
            tauri::async_runtime::spawn(async move {
                let state = controller(&app);
                tokio::join!(async { state.client.lock().await.stop().await }, async { state.antigravity_client.lock().await.stop().await });
            });
        } else {
            let app = app.clone();
            tauri::async_runtime::spawn(async move {
                tokio::join!(refresh_quota(&app, true), refresh_antigravity(&app, false), refresh_announcements(&app), refresh_antigravity_announcements(&app));
            });
        }
    }
}

pub async fn notify(app: &AppHandle, title: &str, body: &str, source_url: Option<&str>) {
    let result = match crate::platform::notification_permission(false).await {
        Ok(status)
            if matches!(
                status.permission,
                crate::platform::NotificationPermission::Granted
                    | crate::platform::NotificationPermission::System
            ) =>
        {
            crate::platform::send_notification(app, title, body, source_url).await
        }
        Ok(_) => return,
        Err(error) => Err(error),
    };
    if let Err(error) = result {
        controller(app).store.lock().unwrap().snapshot.error = Some(error);
    }
}

pub async fn refresh_quota(app: &AppHandle, force: bool) {
    let state = controller(app);
    let mut activity = state.active.subscribe();
    {
        let mut store = state.store.lock().unwrap();
        if !*activity.borrow()
            || store.snapshot.quota.refreshing
            || !store.saved.schedule.can_refresh(force, now())
        {
            return;
        }
        store.snapshot.quota.refreshing = true;
    }
    let mut client = state.client.lock().await;
    let result = tokio::select! {
        result = client.sample() => Some(result),
        _ = activity.changed() => { client.stop().await; None },
    };
    drop(client);
    let mut messages = Vec::new();
    {
        let mut store = state.store.lock().unwrap();
        store.snapshot.quota.refreshing = false;
        if !*activity.borrow() {
            return;
        }
        match result {
            Some(Ok(sample)) => {
                let time = now();
                let settings = store.snapshot.settings.clone();
                let continuous = store.continuous;
                store.saved.quota_history.observe(
                    &sample.fingerprint,
                    &sample.windows,
                    time,
                    continuous,
                    settings.refresh_interval as f64 * 3.0,
                );
                store.continuous = true;
                let recovered = store
                    .saved
                    .recovery
                    .observe(&sample.fingerprint, &sample.windows);
                if settings.recovery_notifications && !recovered.is_empty() {
                    let labels = recovered
                        .iter()
                        .map(|window| window.display_label())
                        .collect::<Vec<_>>()
                        .join("、");
                    messages.push((
                        "Codex 额度已恢复至 100%".to_string(),
                        format!("{labels}已恢复，可以继续使用。"),
                    ));
                }
                store
                    .saved
                    .reminded_credits
                    .retain(|_, expiration| *expiration > time);
                store.saved.deadline_reminders.prune(time);
                let mut expirations = Vec::new();
                if let Some(credits) = &sample.reset_credits {
                    for credit in credits.available_credits() {
                        if let Some(expiration) = credit.expires_at.filter(|v| *v > time) {
                            let key = fingerprint(&format!("{}:{}", sample.fingerprint, credit.id));
                            let previously_reminded =
                                store.saved.reminded_credits.remove(&key).is_some();
                            let due = store.saved.deadline_reminders.observe(
                                format!("credit:{key}"),
                                expiration,
                                time,
                                &settings.reset_credit_reminder_minutes,
                            );
                            if due.is_some() && !previously_reminded {
                                expirations.push(expiration);
                            }
                        }
                    }
                }
                if settings.reset_credit_reminders && !expirations.is_empty() {
                    let earliest = expirations.iter().copied().fold(f64::INFINITY, f64::min);
                    let when = chrono::DateTime::from_timestamp(earliest as i64, 0)
                        .map(|d| {
                            d.with_timezone(&chrono::Local)
                                .format("%m-%d %H:%M")
                                .to_string()
                        })
                        .unwrap_or_default();
                    messages.push((
                        "Codex 重置卡即将到期".into(),
                        format!(
                            "{} 张重置卡即将到期，最早于 {when} 到期。",
                            expirations.len()
                        ),
                    ));
                }
                let mut upcoming_resets = Vec::new();
                for window in &sample.windows {
                    let Some(deadline) = window.resets_at.filter(|deadline| *deadline > time)
                    else {
                        continue;
                    };
                    // A lead time spanning an entire quota window is not a pre-reset warning.
                    let minutes: Vec<_> = settings
                        .quota_reset_reminder_minutes
                        .iter()
                        .copied()
                        .filter(|minutes| {
                            window
                                .duration_minutes
                                .is_none_or(|duration| i64::from(*minutes) < duration)
                        })
                        .collect();
                    let key = fingerprint(&format!("{}:{}", sample.fingerprint, window.id));
                    let due = store.saved.deadline_reminders.observe(
                        format!("quota:{key}"),
                        deadline,
                        time,
                        &minutes,
                    );
                    if due.is_some() && window.remaining() > 0.0 {
                        let remaining = if window.remaining() < 0.1 {
                            "不足 0.1".into()
                        } else {
                            format!("{:.1}", window.remaining())
                        };
                        let when = chrono::DateTime::from_timestamp(deadline as i64, 0)
                            .map(|date| {
                                date.with_timezone(&chrono::Local)
                                    .format("%m-%d %H:%M")
                                    .to_string()
                            })
                            .unwrap_or_default();
                        upcoming_resets.push(format!(
                            "{}还剩 {remaining}%，将于 {when} 重置。",
                            window.display_label()
                        ));
                    }
                }
                if settings.quota_reset_reminders && !upcoming_resets.is_empty() {
                    messages.push((
                        "Codex 额度即将重置".into(),
                        format!("{}\n可在重置前使用剩余额度。", upcoming_resets.join("\n")),
                    ));
                }
                store.saved.schedule.succeeded();
                store.saved.schedule.next_attempt = time + settings.refresh_interval as f64;
                store.snapshot.quota = QuotaSnapshot {
                    windows: sample.windows,
                    reset_credits: sample.reset_credits,
                    history: store.saved.quota_history.series.clone(),
                    error: None,
                    last_success: Some(time),
                    refreshing: false,
                };
            }
            Some(Err(error)) => {
                store.continuous = false;
                let delay = store.saved.schedule.failed(error.retry_after, now());
                let stale = if store.snapshot.quota.last_success.is_some() {
                    " 上次数据已过期。"
                } else {
                    ""
                };
                store.snapshot.quota.error = Some(format!(
                    "{} {} 秒后重试。{stale}",
                    error.message,
                    delay.ceil() as u64
                ));
            }
            None => {
                store.continuous = false;
            }
        }
        // Persist the observed baseline before notifying, including while reminders are disabled.
        if store.persist().is_err() {
            messages.clear();
        }
    }
    for (title, body) in messages {
        notify(app, &title, &body, None).await;
    }
    state.emit(app);
}

pub async fn refresh_antigravity(app: &AppHandle, force: bool) {
    let state = controller(app);
    let mut activity = state.antigravity_active.subscribe();
    {
        let mut store = state.store.lock().unwrap();
        if !*activity.borrow()
            || store.snapshot.antigravity.refreshing
            || (!force && store.snapshot.antigravity.requires_action)
            || !store.saved.antigravity_schedule.can_refresh(force, now())
        {
            return;
        }
        store.snapshot.antigravity.refreshing = true;
    }
    state.emit(app);
    let mut client = state.antigravity_client.lock().await;
    let result = tokio::select! {
        result = client.sample() => Some(result),
        _ = activity.changed() => { client.stop().await; None },
    };
    drop(client);
    {
        let mut store = state.store.lock().unwrap();
        store.snapshot.antigravity.refreshing = false;
        if *activity.borrow() {
            match result {
                Some(Ok(groups)) => {
                    store.saved.antigravity_schedule.succeeded();
                    store.saved.antigravity_schedule.next_attempt = now() + store.snapshot.settings.refresh_interval as f64;
                    store.snapshot.antigravity = AntigravitySnapshot {
                        groups,
                        last_success: Some(now()),
                        ..Default::default()
                    };
                }
                Some(Err(error)) => {
                    let delay = store.saved.antigravity_schedule.failed(error.retry_after, now());
                    store.snapshot.antigravity.requires_action = error.requires_action;
                    store.snapshot.antigravity.error = Some(if error.requires_action {
                        error.message
                    } else {
                        format!("{} {} 秒后重试。", error.message, delay.ceil() as u64)
                    });
                }
                None => {}
            }
            let _ = store.persist();
        }
    }
    state.emit(app);
}

pub async fn scan_usage(app: &AppHandle, rescan: bool) {
    let state = controller(app);
    let codex_home = {
        let mut store = state.store.lock().unwrap();
        if state.preview || store.snapshot.usage.refreshing {
            return;
        }
        store.snapshot.usage.refreshing = true;
        std::path::PathBuf::from(&store.snapshot.usage.source)
    };
    state.emit(app);
    let reader = state.reader.clone();
    let scan = tauri::async_runtime::spawn_blocking(move || {
        let scan = reader.lock().unwrap().scan(rescan);
        let (mut titles, warnings) = crate::session_titles::read(&codex_home);
        let sessions: std::collections::BTreeSet<_> = scan.records.iter().map(|record| &record.session).collect();
        titles.retain(|session, _| sessions.contains(session));
        (scan, titles, warnings)
    }).await;
    {
        let mut store = state.store.lock().unwrap();
        store.snapshot.usage.refreshing = false;
        match scan {
            Ok((scan, titles, title_warnings)) => {
                let changed = store.snapshot.usage.records.len() != scan.records.len()
                    || !store
                        .snapshot
                        .usage
                        .records
                        .iter()
                        .zip(&scan.records)
                        .all(|(old, new)| old.same_usage(new));
                if changed {
                    store.snapshot.usage.records = scan.records;
                }
                store.snapshot.usage.project_roots = scan.project_roots;
                store.snapshot.usage.session_titles = titles;
                store.snapshot.usage.warnings = scan.warnings;
                store.snapshot.usage.warnings.extend(title_warnings);
                if let Some(error) = scan.history_error {
                    store.snapshot.usage.warnings.push(error);
                }
                store.snapshot.usage.file_count = scan.file_count;
                store.snapshot.usage.scanned_at = Some(now());
                if changed {
                    store.reprice();
                }
            }
            Err(_) => store.snapshot.usage.warnings = vec!["用量扫描未完成，请重新扫描。".into()],
        }
    }
    state.emit(app);
}

pub async fn refresh_announcements(app: &AppHandle) {
    refresh_announcement_feed(app, false).await;
}

pub async fn refresh_antigravity_announcements(app: &AppHandle) {
    refresh_announcement_feed(app, true).await;
}

async fn refresh_announcement_feed(app: &AppHandle, antigravity: bool) {
    let state = controller(app);
    let mut activity = if antigravity { state.antigravity_active.subscribe() } else { state.active.subscribe() };
    let etag = {
        let mut store = state.store.lock().unwrap();
        let Store { saved, snapshot, .. } = &mut *store;
        let (saved, snapshot) = if antigravity {
            (&mut saved.antigravity_announcements, &mut snapshot.antigravity_announcements)
        } else {
            (&mut saved.announcements, &mut snapshot.announcements)
        };
        if !*activity.borrow() || snapshot.refreshing || now() < saved.next_request { return; }
        snapshot.refreshing = true;
        saved.next_request = now() + 600.0;
        let etag = saved.feed.as_ref().and(saved.etag.clone());
        let _ = store.persist();
        etag
    };
    state.emit(app);
    let request = async {
        let mut request = state
            .http
            .get(if antigravity { "https://aihot.news/api/v1/antigravity-resets/recent" } else { "https://aihot.news/api/v1/codex-resets/recent" })
            .header("Accept", "application/json");
        if let Some(etag) = etag {
            request = request.header("If-None-Match", etag);
        }
        let response = request
            .send()
            .await
            .map_err(|_| ("无法读取 AIHOT 动态，请检查网络。".to_string(), None))?;
        let status = response.status();
        if status.as_u16() == 304 {
            return Ok(None);
        }
        if !status.is_success() {
            let retry = if [429, 503].contains(&status.as_u16()) {
                let value = response
                    .headers()
                    .get("Retry-After")
                    .and_then(|v| v.to_str().ok())
                    .unwrap_or("");
                let seconds = value.parse::<f64>().ok().or_else(|| {
                    chrono::DateTime::parse_from_rfc2822(value)
                        .ok()
                        .map(|v| v.timestamp() as f64 - now())
                });
                Some(
                    seconds
                        .filter(|v| v.is_finite())
                        .unwrap_or(600.0)
                        .max(600.0),
                )
            } else {
                None
            };
            return Err((
                format!("AIHOT 请求失败（HTTP {}），稍后自动重试。", status.as_u16()),
                retry,
            ));
        }
        let etag = response
            .headers()
            .get("ETag")
            .and_then(|v| v.to_str().ok())
            .map(String::from);
        let bytes = response
            .bytes()
            .await
            .map_err(|_| ("无法读取 AIHOT 动态。".to_string(), None))?;
        let feed = if antigravity { ResetAnnouncementFeed::decode_antigravity(&bytes) } else { ResetAnnouncementFeed::decode(&bytes) }.map_err(|error| (error, None))?;
        Ok(Some((feed, etag)))
    };
    let response = tokio::select! { result=request => Some(result), _=activity.changed() => None };
    let mut notifications = Vec::new();
    {
        let mut store = state.store.lock().unwrap();
        let Store { saved, snapshot, .. } = &mut *store;
        let enabled = if antigravity { snapshot.settings.antigravity_announcement_notifications } else { snapshot.settings.announcement_notifications };
        let (saved, snapshot) = if antigravity {
            (&mut saved.antigravity_announcements, &mut snapshot.antigravity_announcements)
        } else {
            (&mut saved.announcements, &mut snapshot.announcements)
        };
        snapshot.refreshing = false;
        if !*activity.borrow() { return; }
        match response {
            Some(Ok(updated)) => {
                if let Some((feed, etag)) = updated {
                    saved.feed = Some(feed);
                    saved.etag = etag;
                }
                if let Some(feed) = &saved.feed {
                    notifications = saved.tracker.observe(&feed.events, enabled, now());
                    snapshot.events = feed.events.clone();
                    snapshot.source_status = feed.source_status(now());
                    snapshot.error = None;
                    snapshot.last_success = Some(now());
                } else {
                    snapshot.error = Some("AIHOT 未返回首次快照。".into());
                }
            }
            Some(Err((error, retry))) => {
                if let Some(retry) = retry { saved.next_request = now() + retry; }
                snapshot.error = Some(error);
                snapshot.source_status = saved.feed.as_ref().and_then(|feed| feed.source_status(now()));
            }
            None => {}
        }
        if store.persist().is_err() {
            notifications.clear();
        }
    }
    for event in notifications {
        if let Some(post) = event.latest_post() {
            notify(
                app,
                &if antigravity { event.antigravity_notification_title() } else { event.notification_title() },
                &post.text,
                Some(&post.url),
            )
            .await;
        }
    }
    state.emit(app);
}

pub fn start(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let state = controller(&app);
        if state.preview {
            return;
        }
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            interval.tick().await;
            if state.paused.load(Ordering::Relaxed) {
                continue;
            }
            let (quota, announcements, antigravity, antigravity_announcements, usage, update) = {
                let store = state.store.lock().unwrap();
                let visible = app.get_webview_window("main").is_some_and(|w| {
                    w.is_visible().unwrap_or(false) && !w.is_minimized().unwrap_or(false)
                });
                (
                    store.snapshot.settings.monitoring_enabled
                        && store.saved.schedule.can_refresh(false, now()),
                    store.snapshot.settings.monitoring_enabled
                        && now() >= store.saved.announcements.next_request,
                    store.snapshot.settings.antigravity_enabled
                        && !store.snapshot.antigravity.requires_action
                        && store.saved.antigravity_schedule.can_refresh(false, now()),
                    store.snapshot.settings.antigravity_enabled
                        && now() >= store.saved.antigravity_announcements.next_request,
                    visible
                        && store
                            .snapshot
                            .usage
                            .scanned_at
                            .is_none_or(|t| now() - t >= 30.0),
                    store.snapshot.settings.automatic_updates
                        && now() >= store.saved.next_update_check,
                )
            };
            if quota {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    refresh_quota(&app, false).await;
                });
            }
            if announcements {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    refresh_announcements(&app).await;
                });
            }
            if antigravity {
                let app = app.clone();
                tauri::async_runtime::spawn(async move { refresh_antigravity(&app, false).await; });
            }
            if antigravity_announcements {
                let app = app.clone();
                tauri::async_runtime::spawn(async move { refresh_antigravity_announcements(&app).await; });
            }
            if usage {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    scan_usage(&app, false).await;
                });
            }
            if update {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    let _ = crate::updates::check(&app).await;
                });
            }
        }
    });
}
