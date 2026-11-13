use quota_core::{
    DeadlineReminderTracker, ModelPricing, QuotaHistory, QuotaSeries, QuotaWindow,
    RateLimitResetCredits, RecoveryTracker, RefreshSchedule, ResetAnnouncement,
    ResetAnnouncementFeed, ResetAnnouncementTracker, UsageRecord, SWIFT_EPOCH_OFFSET,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

pub fn now() -> f64 {
    chrono::Utc::now().timestamp_millis() as f64 / 1000.0
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub monitoring_enabled: bool,
    pub antigravity_enabled: bool,
    pub antigravity_announcement_notifications: bool,
    pub antigravity_show_tray: bool,
    pub recovery_notifications: bool,
    pub reset_credit_reminders: bool,
    pub reset_credit_reminder_minutes: Vec<u32>,
    pub quota_reset_reminders: bool,
    pub quota_reset_reminder_minutes: Vec<u32>,
    pub announcement_notifications: bool,
    pub show_tray: bool,
    pub launch_at_login: bool,
    pub animations: bool,
    pub refresh_interval: u64,
    pub automatic_updates: bool,
    pub today_metrics: Vec<String>,
    pub detail_columns: Vec<String>,
}

impl Settings {
    pub fn from_preferences(p: &BTreeMap<String, Value>) -> Self {
        let flag = |key: &str, default| p.get(key).and_then(Value::as_bool).unwrap_or(default);
        let reminder_minutes = |key: &str, default| {
            p.get(key)
                .and_then(|value| serde_json::from_value::<Vec<u32>>(value.clone()).ok())
                .filter(|minutes| !minutes.is_empty() && minutes.iter().all(|value| *value > 0))
                .map(|mut minutes| {
                    minutes.sort_unstable_by(|a, b| b.cmp(a));
                    minutes.dedup();
                    minutes
                })
                .unwrap_or_else(|| vec![default])
        };
        let today = p
            .get("usage.sidebarToday.v1")
            .and_then(Value::as_u64)
            .unwrap_or(1);
        Self {
            monitoring_enabled: flag("service.codex.enabled", true),
            antigravity_enabled: flag("antigravity.cli.enabled", false),
            antigravity_announcement_notifications: flag("antigravity.cli.announcementNotifications", false),
            antigravity_show_tray: flag("antigravity.cli.showTray", true),
            recovery_notifications: flag("service.codex.notifications", true),
            reset_credit_reminders: flag("resetCredits.expirationReminders", false),
            reset_credit_reminder_minutes: reminder_minutes("resetCredits.reminderMinutes", 1440),
            quota_reset_reminders: flag("quota.resetReminders", false),
            quota_reset_reminder_minutes: reminder_minutes("quota.resetReminderMinutes", 120),
            announcement_notifications: flag("resetAnnouncements.notifications", false),
            show_tray: flag(
                "menuBar.codex.visible",
                flag("menuBar.visible", true) && flag("service.codex.menuBar", true),
            ),
            launch_at_login: flag("launchAtLogin", false),
            animations: flag("appearance.animationsEnabled", true),
            refresh_interval: p
                .get("quota.refreshIntervalSeconds")
                .and_then(Value::as_u64)
                .unwrap_or(60)
                .max(30),
            automatic_updates: flag(
                "SUEnableAutomaticChecks",
                flag("updates.automaticallyChecks", true),
            ),
            today_metrics: [(1, "tokens"), (2, "cost"), (4, "records"), (8, "hitRate")]
                .into_iter()
                .filter(|(bit, _)| today & bit != 0)
                .map(|(_, name)| name.into())
                .collect(),
            detail_columns: [
                ("speed", true),
                ("firstToken", true),
                ("cacheWrite", false),
                ("billingTier", false),
            ]
            .into_iter()
            .filter(|(name, default)| flag(&format!("usage.columns.{name}"), *default))
            .map(|(name, _)| name.into())
            .collect(),
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.refresh_interval < 30 || self.refresh_interval > i32::MAX as u64 {
            return Err("刷新间隔必须为 30 秒至 2147483647 秒。".into());
        }
        for minutes in [
            &self.reset_credit_reminder_minutes,
            &self.quota_reset_reminder_minutes,
        ] {
            if minutes.is_empty() || minutes.contains(&0) {
                return Err("请至少设置一个提醒时间，提前时间须为正整数分钟。".into());
            }
            let unique: std::collections::BTreeSet<_> = minutes.iter().collect();
            if unique.len() != minutes.len() {
                return Err("提醒时间不能重复。".into());
            }
        }
        if self
            .today_metrics
            .iter()
            .any(|v| !["tokens", "cost", "records", "hitRate"].contains(&v.as_str()))
            || self.detail_columns.iter().any(|v| {
                !["speed", "firstToken", "cacheWrite", "billingTier"].contains(&v.as_str())
            })
        {
            return Err("用量显示设置无效。".into());
        }
        Ok(())
    }

    pub fn save_into(&self, p: &mut BTreeMap<String, Value>) {
        for (key, value) in [
            ("service.codex.enabled", self.monitoring_enabled),
            ("antigravity.cli.enabled", self.antigravity_enabled),
            ("antigravity.cli.announcementNotifications", self.antigravity_announcement_notifications),
            ("antigravity.cli.showTray", self.antigravity_show_tray),
            ("service.codex.notifications", self.recovery_notifications),
            (
                "resetCredits.expirationReminders",
                self.reset_credit_reminders,
            ),
            (
                "resetAnnouncements.notifications",
                self.announcement_notifications,
            ),
            ("quota.resetReminders", self.quota_reset_reminders),
            ("menuBar.codex.visible", self.show_tray),
            ("launchAtLogin", self.launch_at_login),
            ("appearance.animationsEnabled", self.animations),
            ("updates.automaticallyChecks", self.automatic_updates),
            ("SUEnableAutomaticChecks", self.automatic_updates),
        ] {
            p.insert(key.into(), json!(value));
        }
        p.insert(
            "resetCredits.reminderMinutes".into(),
            json!(self.reset_credit_reminder_minutes),
        );
        p.insert(
            "quota.resetReminderMinutes".into(),
            json!(self.quota_reset_reminder_minutes),
        );
        p.insert(
            "quota.refreshIntervalSeconds".into(),
            json!(self.refresh_interval),
        );
        let bits: u64 = [(1, "tokens"), (2, "cost"), (4, "records"), (8, "hitRate")]
            .into_iter()
            .filter(|(_, name)| self.today_metrics.iter().any(|value| value == name))
            .map(|(bit, _)| bit)
            .sum();
        p.insert("usage.sidebarToday.v1".into(), json!(bits));
        for key in ["speed", "firstToken", "cacheWrite", "billingTier"] {
            p.insert(
                format!("usage.columns.{key}"),
                json!(self.detail_columns.iter().any(|v| v == key)),
            );
        }
    }
}

#[derive(Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaSnapshot {
    pub windows: Vec<QuotaWindow>,
    pub reset_credits: Option<RateLimitResetCredits>,
    pub history: BTreeMap<String, QuotaSeries>,
    pub error: Option<String>,
    pub last_success: Option<f64>,
    pub refreshing: bool,
}

#[derive(Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AnnouncementSnapshot {
    pub events: Vec<ResetAnnouncement>,
    pub error: Option<String>,
    pub source_status: Option<String>,
    pub refreshing: bool,
    pub last_success: Option<f64>,
}

#[derive(Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AntigravitySnapshot {
    pub groups: Vec<quota_core::AntigravityGroup>,
    pub error: Option<String>,
    pub last_success: Option<f64>,
    pub refreshing: bool,
    pub requires_action: bool,
}

#[derive(Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageSnapshot {
    pub records: Vec<UsageRecord>,
    pub project_roots: BTreeMap<String, String>,
    pub session_titles: BTreeMap<String, String>,
    pub warnings: Vec<String>,
    pub scanned_at: Option<f64>,
    pub file_count: usize,
    pub refreshing: bool,
    pub source: String,
}

#[derive(Clone, Serialize)]
pub struct DisplayPrice {
    #[serde(flatten)]
    pub price: ModelPricing,
    pub custom: bool,
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateState {
    pub status: String,
    pub version: Option<String>,
    pub notes: Option<String>,
    pub error: Option<String>,
    pub progress: Option<f64>,
    pub can_install: bool,
}
impl Default for UpdateState {
    fn default() -> Self {
        Self {
            status: "idle".into(),
            version: None,
            notes: None,
            error: None,
            progress: None,
            can_install: false,
        }
    }
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSnapshot {
    pub settings: Settings,
    pub quota: QuotaSnapshot,
    pub announcements: AnnouncementSnapshot,
    pub antigravity: AntigravitySnapshot,
    pub antigravity_announcements: AnnouncementSnapshot,
    pub usage: UsageSnapshot,
    pub prices: Vec<DisplayPrice>,
    pub price_date: String,
    pub version: String,
    pub platform: String,
    pub update: UpdateState,
    pub installed_release_notes: Option<String>,
    pub notification_guide_shown: bool,
    pub error: Option<String>,
}

#[derive(Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SavedAnnouncements {
    pub feed: Option<ResetAnnouncementFeed>,
    pub etag: Option<String>,
    pub tracker: ResetAnnouncementTracker,
    pub next_request: f64,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct SavedState {
    pub version: u32,
    pub preferences: BTreeMap<String, Value>,
    pub recovery: RecoveryTracker,
    pub quota_history: QuotaHistory,
    pub schedule: RefreshSchedule,
    pub reminded_credits: BTreeMap<String, f64>,
    pub deadline_reminders: DeadlineReminderTracker,
    pub announcements: SavedAnnouncements,
    pub antigravity_schedule: RefreshSchedule,
    pub antigravity_announcements: SavedAnnouncements,
    pub catalog: BTreeMap<String, ModelPricing>,
    pub overrides: BTreeMap<String, ModelPricing>,
    pub price_date: String,
    pub next_update_check: f64,
}

impl Default for SavedState {
    fn default() -> Self {
        Self {
            version: 1,
            preferences: BTreeMap::new(),
            recovery: RecoveryTracker::default(),
            quota_history: QuotaHistory::default(),
            schedule: RefreshSchedule::default(),
            reminded_credits: BTreeMap::new(),
            deadline_reminders: DeadlineReminderTracker::default(),
            announcements: SavedAnnouncements::default(),
            antigravity_schedule: RefreshSchedule::default(),
            antigravity_announcements: SavedAnnouncements::default(),
            catalog: quota_core::bundled_prices(),
            overrides: BTreeMap::new(),
            price_date: quota_core::BUNDLED_PRICE_DATE.into(),
            next_update_check: 0.0,
        }
    }
}

impl SavedState {
    pub fn load(path: &Path) -> Result<Self, String> {
        match std::fs::read(path) {
            Ok(bytes) => {
                let mut saved: Self = serde_json::from_slice(&bytes)
                    .map_err(|_| "设置文件无法读取；原文件已保留，请修复后重新打开。")?;
                if saved.version != 1 {
                    return Err("设置版本不兼容；原文件已保留，请使用兼容版本。".into());
                }
                saved.catalog.retain(|_, price| price.is_valid());
                saved.overrides.retain(|_, price| price.is_valid());
                Ok(saved)
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Self::migrate_legacy(),
            Err(_) => Err("无法读取设置文件，请检查访问权限。".into()),
        }
    }

    fn migrate_legacy() -> Result<Self, String> {
        let mut saved = Self::default();
        #[cfg(target_os = "macos")]
        if std::env::var_os("CODEX_QUOTA_DATA_DIR").is_none() {
            let path = dirs::home_dir()
                .ok_or("无法找到用户目录")?
                .join("Library/Preferences/local.codexquotadock.app.plist");
            if !path.exists() {
                return Ok(saved);
            }
            let plist =
                plist::Value::from_file(path).map_err(|_| "旧版偏好读取失败；原文件已保留。")?;
            let dictionary = plist
                .as_dictionary()
                .ok_or("旧版偏好格式不兼容；原文件已保留。")?;
            for (key, value) in dictionary {
                if let Some(v) = value.as_boolean() {
                    saved.preferences.insert(key.clone(), json!(v));
                } else if let Some(v) = value.as_signed_integer() {
                    saved.preferences.insert(key.clone(), json!(v));
                } else if let Some(v) = value.as_string() {
                    saved.preferences.insert(key.clone(), json!(v));
                }
            }
            let data = |key: &str| -> Result<Option<Value>, String> {
                dictionary
                    .get(key)
                    .and_then(plist::Value::as_data)
                    .map(|bytes| {
                        serde_json::from_slice(bytes)
                            .map_err(|_| "旧版保存数据格式不兼容；原文件已保留。".into())
                    })
                    .transpose()
            };
            if let Some(value) = data("recoveryState.v2")? {
                saved.recovery.state = value
                    .get("states")
                    .and_then(|v| v.get("codex"))
                    .map(|v| serde_json::from_value(v.clone()))
                    .transpose()
                    .map_err(|_| "旧版通知状态无法迁移。")?;
            } else if let Some(value) = data("recoveryState.v1")? {
                saved.recovery.state =
                    Some(serde_json::from_value(value).map_err(|_| "旧版通知状态无法迁移。")?);
            }
            if let Some(mut value) = data("quotaHistory.v1")? {
                convert_swift_dates(&mut value, "");
                saved.quota_history =
                    serde_json::from_value(value).map_err(|_| "旧版额度历史无法迁移。")?;
            }
            if let Some(mut value) = data("resetAnnouncements.state.v1")? {
                convert_swift_dates(&mut value, "");
                saved.announcements =
                    serde_json::from_value(value).map_err(|_| "旧版重置动态无法迁移。")?;
            }
            if let Some(mut value) = data("resetCredits.reminded.v1")? {
                convert_swift_dates(&mut value, "seen");
                saved.reminded_credits =
                    serde_json::from_value(value).map_err(|_| "旧版重置卡提醒无法迁移。")?;
            }
            if let Some(value) = data("usage.pricing.catalog.v1")? {
                saved.catalog =
                    serde_json::from_value(value).map_err(|_| "旧版定价目录无法迁移。")?;
            }
            if let Some(value) = data("usage.pricing.overrides.v1")? {
                saved.overrides =
                    serde_json::from_value(value).map_err(|_| "旧版自定义定价无法迁移。")?;
            }
            if let Some(value) = saved
                .preferences
                .get("usage.pricing.date")
                .and_then(Value::as_str)
            {
                saved.price_date = value.into();
            }
        }
        saved.catalog.retain(|_, price| price.is_valid());
        saved.overrides.retain(|_, price| price.is_valid());
        Ok(saved)
    }

    pub fn prices(&self) -> BTreeMap<String, ModelPricing> {
        let mut prices = self.catalog.clone();
        prices.extend(self.overrides.clone());
        prices.retain(|_, price| price.service == "codex");
        prices
    }
}

#[cfg(target_os = "macos")]
fn convert_swift_dates(value: &mut Value, field: &str) {
    let date_fields = [
        "date",
        "lastObservation",
        "resetsAt",
        "nextRequest",
        "checkedAt",
        "lastCollectedAt",
        "lastVerifiedAt",
        "confirmedAt",
        "through",
        "updatedAt",
        "publishedAt",
    ];
    match value {
        Value::Object(fields) => {
            for (key, value) in fields {
                convert_swift_dates(value, if field == "seen" { "date" } else { key });
            }
        }
        Value::Array(values) => {
            for value in values {
                convert_swift_dates(value, field);
            }
        }
        Value::Number(number) if date_fields.contains(&field) => {
            if let Some(seconds) = number.as_f64() {
                *value = json!(seconds + SWIFT_EPOCH_OFFSET);
            }
        }
        _ => {}
    }
}

pub struct Store {
    pub saved: SavedState,
    pub snapshot: AppSnapshot,
    pub path: PathBuf,
    pub writable: bool,
    pub continuous: bool,
    pub updating_prices: bool,
}

impl Store {
    pub fn commit(&mut self, saved: SavedState) -> Result<(), String> {
        let previous = std::mem::replace(&mut self.saved, saved);
        let result = self.persist();
        if result.is_err() {
            self.saved = previous;
        }
        result
    }

    pub fn persist(&mut self) -> Result<(), String> {
        if !self.writable {
            return Err(self
                .snapshot
                .error
                .clone()
                .unwrap_or_else(|| "设置无法保存".into()));
        }
        let result = quota_core::write_json_atomic(&self.path, &self.saved);
        self.snapshot.error = result.as_ref().err().cloned();
        result
    }

    pub fn reprice(&mut self) {
        let prices = self.saved.prices();
        for record in &mut self.snapshot.usage.records {
            record.cost = quota_core::price_record(record, &prices).map(|v| v.to_string());
        }
        let mut display_prices = prices.clone();
        for record in self
            .snapshot
            .usage
            .records
            .iter()
            .filter(|record| record.service == "codex")
        {
            let key = format!("codex:{}", record.model.to_lowercase());
            display_prices.entry(key).or_insert_with(|| {
                let mut price = quota_core::lookup_price("codex", &record.model, &prices)
                    .cloned()
                    .unwrap_or_else(|| ModelPricing {
                        service: "codex".into(),
                        model: record.model.clone(),
                        rates: Default::default(),
                        context_threshold: None,
                        long_context_rates: None,
                        fast_multiplier: None,
                        ultrafast_multiplier: None,
                    });
                price.model = record.model.clone();
                price
            });
        }
        self.snapshot.prices = display_prices
            .into_iter()
            .map(|(key, price)| DisplayPrice {
                custom: self.saved.overrides.contains_key(&key),
                price,
            })
            .collect();
        self.snapshot
            .prices
            .sort_by(|left, right| left.price.model.cmp(&right.price.model));
        self.snapshot.price_date = self.saved.price_date.clone();
    }
}
