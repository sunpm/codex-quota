use crate::parse_timestamp;
use serde::{Deserialize, Deserializer, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Deserialize)]
#[serde(untagged)]
enum Timestamp {
    Seconds(f64),
    Iso(String),
}

impl Timestamp {
    fn seconds<E: serde::de::Error>(self) -> Result<f64, E> {
        match self {
            Self::Seconds(value) if value.is_finite() => Ok(value),
            Self::Iso(value) => {
                parse_timestamp(&value).ok_or_else(|| E::custom("Invalid announcement date"))
            }
            _ => Err(E::custom("Invalid announcement date")),
        }
    }
}

fn timestamp<'de, D: Deserializer<'de>>(deserializer: D) -> Result<f64, D::Error> {
    Timestamp::deserialize(deserializer)?.seconds()
}

fn optional_timestamp<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Option<f64>, D::Error> {
    Option::<Timestamp>::deserialize(deserializer)?
        .map(Timestamp::seconds)
        .transpose()
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResetAnnouncementFeed {
    pub schema_version: u32,
    #[serde(default, deserialize_with = "optional_timestamp")]
    pub checked_at: Option<f64>,
    pub events: Vec<ResetAnnouncement>,
    pub monitor: Option<AnnouncementMonitor>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AnnouncementMonitor {
    pub status: String,
    #[serde(default, deserialize_with = "optional_timestamp")]
    pub last_collected_at: Option<f64>,
    #[serde(default, deserialize_with = "optional_timestamp")]
    pub last_verified_at: Option<f64>,
}

impl ResetAnnouncementFeed {
    pub fn decode(data: &[u8]) -> Result<Self, String> {
        Self::decode_from_author(data, "thsottiaux")
    }

    pub fn decode_antigravity(data: &[u8]) -> Result<Self, String> {
        Self::decode_from_author(data, "_mohansolo")
    }

    fn decode_from_author(data: &[u8], author: &str) -> Result<Self, String> {
        let feed: Self = serde_json::from_slice(data).map_err(|_| "AIHOT 数据格式暂不兼容。")?;
        let ids: BTreeSet<_> = feed.events.iter().map(|event| &event.id).collect();
        if feed.schema_version != 1
            || ids.len() != feed.events.len()
            || feed.events.iter().any(|event| {
                event.id.is_empty()
                    || event.posts.iter().any(|post| {
                        ResetAnnouncementPost::source_url_for_author(&post.id, author).as_ref()
                            != Some(&post.url)
                    })
            })
        {
            return Err("AIHOT 数据格式暂不兼容。".into());
        }
        Ok(feed)
    }
    pub fn source_status(&self, now: f64) -> Option<String> {
        match self.monitor.as_ref().map(|monitor| monitor.status.as_str()) {
            Some("attention") => return Some("AIHOT 数据待核实".into()),
            Some("delayed") => return Some("AIHOT 更新延迟".into()),
            _ => {}
        }
        let Some(date) = self
            .monitor
            .as_ref()
            .and_then(|m| m.last_verified_at)
            .or(self.checked_at)
        else {
            return Some("来源更新时间未知".into());
        };
        if now - date > 1800.0 {
            return Some("AIHOT 数据已过期".into());
        }
        self.monitor
            .as_ref()
            .filter(|m| m.status != "healthy")
            .map(|_| "AIHOT 监测状态未知".into())
    }
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AnnouncementKind {
    DirectReset,
    ResetCredit,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AnnouncementPhase {
    Announced,
    Confirmed,
}

impl AnnouncementPhase {
    fn key(self) -> &'static str {
        match self {
            Self::Announced => "announced",
            Self::Confirmed => "confirmed",
        }
    }
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum AnnouncementDisplayStatus {
    Announced,
    Confirmed,
    InProgress,
    ExpiredUnconfirmed,
    LikelyCompleted,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AnnouncementPresentation {
    pub status: AnnouncementDisplayStatus,
    pub scope_label: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AnnouncementWindow {
    #[serde(deserialize_with = "timestamp")]
    pub through: f64,
    pub label: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResetAnnouncement {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: AnnouncementKind,
    pub display_label: Option<String>,
    pub status: AnnouncementPhase,
    pub presentation: Option<AnnouncementPresentation>,
    #[serde(default, deserialize_with = "optional_timestamp")]
    pub confirmed_at: Option<f64>,
    pub confirmation_basis: Option<String>,
    pub schedule: Option<AnnouncementWindow>,
    pub estimate: Option<AnnouncementWindow>,
    #[serde(deserialize_with = "timestamp")]
    pub updated_at: f64,
    pub posts: Vec<ResetAnnouncementPost>,
}

impl ResetAnnouncement {
    pub fn latest_post(&self) -> Option<&ResetAnnouncementPost> {
        self.posts
            .iter()
            .max_by(|a, b| a.published_at.total_cmp(&b.published_at))
    }
    pub fn display_status(&self, now: f64) -> AnnouncementDisplayStatus {
        use AnnouncementDisplayStatus::*;
        if self.status == AnnouncementPhase::Confirmed {
            return Confirmed;
        }
        let display = self.presentation.as_ref().map_or(Announced, |p| p.status);
        if matches!(display, Announced | InProgress)
            && self
                .estimate
                .as_ref()
                .or(self.schedule.as_ref())
                .is_some_and(|window| now > window.through)
        {
            return ExpiredUnconfirmed;
        }
        if display == Confirmed {
            Announced
        } else {
            display
        }
    }
    pub fn status_text(&self, now: f64) -> &'static str {
        use AnnouncementDisplayStatus::*;
        match self.display_status(now) {
            Announced => "已预告",
            InProgress => "正在生效",
            Confirmed => match self.confirmation_basis.as_deref() {
                Some("source_post") => "Tibo 已确认",
                Some("receipt_review") => "AIHOT 到账核实",
                _ => "公告已确认",
            },
            ExpiredUnconfirmed | LikelyCompleted => "已过预计时间，未确认",
        }
    }
    pub fn notification_title(&self) -> String {
        self.notification_title_from("Tibo")
    }
    pub fn antigravity_notification_title(&self) -> String {
        format!("Antigravity · {}", self.notification_title_from("Varun"))
    }
    fn notification_title_from(&self, author: &str) -> String {
        let action = if self.kind == AnnouncementKind::ResetCredit {
            "发放重置卡"
        } else {
            "重置"
        };
        if self.status == AnnouncementPhase::Announced {
            format!("{author} 预告{action}")
        } else if self.confirmation_basis.as_deref() == Some("source_post") {
            format!("{author} 已确认{action}")
        } else {
            format!("AIHOT 已核实{action}公告")
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResetAnnouncementPost {
    pub id: String,
    #[serde(deserialize_with = "timestamp")]
    pub published_at: f64,
    pub text: String,
    pub url: String,
}

impl ResetAnnouncementPost {
    pub fn source_url(id: &str) -> Option<String> {
        Self::source_url_for_author(id, "thsottiaux")
    }

    fn source_url_for_author(id: &str, author: &str) -> Option<String> {
        (!id.is_empty() && id.bytes().all(|c| c.is_ascii_digit()))
            .then(|| format!("https://x.com/{author}/status/{id}"))
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct ResetAnnouncementTracker {
    pub has_baseline: bool,
    pub seen: BTreeMap<String, f64>,
}

impl ResetAnnouncementTracker {
    pub fn observe(
        &mut self,
        events: &[ResetAnnouncement],
        notify: bool,
        now: f64,
    ) -> Vec<ResetAnnouncement> {
        self.seen.retain(|_, date| now - *date < 30.0 * 86400.0);
        let mut ordered: Vec<_> = events.iter().collect();
        ordered.sort_by(|a, b| a.updated_at.total_cmp(&b.updated_at));
        let mut notifications = Vec::new();
        for event in ordered {
            let keys: Vec<_> = event
                .posts
                .iter()
                .map(|post| format!("{}:{}", post.id, event.status.key()))
                .collect();
            let previously_seen = keys.iter().any(|key| self.seen.contains_key(key));
            let display = event.display_status(now);
            if self.has_baseline
                && notify
                && !previously_seen
                && event
                    .latest_post()
                    .is_some_and(|post| (0.0..=86400.0).contains(&(now - post.published_at)))
                && !matches!(
                    display,
                    AnnouncementDisplayStatus::ExpiredUnconfirmed
                        | AnnouncementDisplayStatus::LikelyCompleted
                )
            {
                notifications.push(event.clone());
            }
            for key in keys {
                self.seen.insert(key, now);
            }
            // 公告确认后也消费预告阶段，避免上游重新归组时补发。
            if event.status == AnnouncementPhase::Confirmed {
                for post in &event.posts {
                    self.seen.insert(format!("{}:announced", post.id), now);
                }
            }
        }
        self.has_baseline = true;
        notifications
    }
}
