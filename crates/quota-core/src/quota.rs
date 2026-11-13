use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimitsResponse {
    pub account_id: Option<String>,
    pub rate_limits: Option<LimitBucket>,
    pub rate_limits_by_limit_id: Option<BTreeMap<String, LimitBucket>>,
    pub rate_limit_reset_credits: Option<RateLimitResetCredits>,
}

impl LimitsResponse {
    pub fn windows(&self) -> Vec<QuotaWindow> {
        let legacy;
        let buckets = match &self.rate_limits_by_limit_id {
            Some(all) if !all.is_empty() => all,
            _ => {
                legacy = self
                    .rate_limits
                    .as_ref()
                    .map(|bucket| {
                        BTreeMap::from([(
                            bucket.limit_id.clone().unwrap_or_else(|| "codex".into()),
                            bucket.clone(),
                        )])
                    })
                    .unwrap_or_default();
                &legacy
            }
        };
        buckets
            .iter()
            .flat_map(|(key, bucket)| {
                [
                    ("primary", &bucket.primary),
                    ("secondary", &bucket.secondary),
                ]
                .into_iter()
                .filter_map(move |(slot, value)| {
                    let value = value.as_ref()?;
                    let used = value.used_percent?;
                    if !used.is_finite() || !(0.0..=100.0).contains(&used) {
                        return None;
                    }
                    Some(QuotaWindow {
                        id: format!("{key}:{slot}:{}", value.window_duration_mins.unwrap_or(0)),
                        bucket: key.clone(),
                        name: bucket.limit_name.clone().unwrap_or_else(|| key.clone()),
                        used_percent: used,
                        duration_minutes: value.window_duration_mins,
                        resets_at: value.resets_at.filter(|v| v.is_finite()),
                        label: None,
                    })
                })
            })
            .collect()
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RateLimitResetCredits {
    pub available_count: u64,
    pub credits: Option<Vec<RateLimitResetCredit>>,
}

impl RateLimitResetCredits {
    pub fn available_credits(&self) -> Vec<&RateLimitResetCredit> {
        if self.available_count == 0 {
            return Vec::new();
        }
        let mut credits: Vec<_> = self
            .credits
            .iter()
            .flatten()
            .filter(|credit| credit.status == "available" && credit.reset_type == "codexRateLimits")
            .collect();
        credits.sort_by(|a, b| {
            a.expires_at
                .unwrap_or(f64::MAX)
                .total_cmp(&b.expires_at.unwrap_or(f64::MAX))
        });
        credits
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RateLimitResetCredit {
    pub id: String,
    pub reset_type: String,
    pub status: String,
    pub expires_at: Option<f64>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimitBucket {
    pub limit_id: Option<String>,
    pub limit_name: Option<String>,
    pub primary: Option<LimitWindow>,
    pub secondary: Option<LimitWindow>,
}

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LimitWindow {
    pub used_percent: Option<f64>,
    pub window_duration_mins: Option<i64>,
    pub resets_at: Option<f64>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuotaWindow {
    pub id: String,
    pub bucket: String,
    pub name: String,
    pub used_percent: f64,
    pub duration_minutes: Option<i64>,
    pub resets_at: Option<f64>,
    pub label: Option<String>,
}

impl QuotaWindow {
    pub fn remaining(&self) -> f64 {
        (100.0 - self.used_percent).clamp(0.0, 100.0)
    }
    pub fn display_label(&self) -> String {
        if let Some(label) = &self.label {
            return label.clone();
        }
        match self.duration_minutes {
            Some(minutes) if minutes > 0 && minutes % 1440 == 0 => {
                format!("{} 天额度", minutes / 1440)
            }
            Some(minutes) if minutes > 0 && minutes % 60 == 0 => {
                format!("{} 小时额度", minutes / 60)
            }
            Some(minutes) if minutes > 0 => format!("{minutes} 分钟额度"),
            _ => "额度".into(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RecoveryState {
    pub account_fingerprint: String,
    pub used_by_window: BTreeMap<String, f64>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct RecoveryTracker {
    pub state: Option<RecoveryState>,
}

impl RecoveryTracker {
    pub fn observe(&mut self, account: &str, windows: &[QuotaWindow]) -> Vec<QuotaWindow> {
        let previous = self
            .state
            .as_ref()
            .filter(|state| state.account_fingerprint == account);
        let recovered = windows
            .iter()
            .filter(|window| {
                previous
                    .and_then(|state| state.used_by_window.get(&window.id))
                    .is_some_and(|old| *old > 0.0 && window.used_percent == 0.0)
            })
            .cloned()
            .collect();
        self.state = Some(RecoveryState {
            account_fingerprint: account.into(),
            used_by_window: windows
                .iter()
                .map(|window| (window.id.clone(), window.used_percent))
                .collect(),
        });
        recovered
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LowQuotaObservation {
    remaining: f64,
    resets_at: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LowQuotaBaseline {
    account_fingerprint: String,
    windows: BTreeMap<String, LowQuotaObservation>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct LowQuotaTracker {
    baseline: Option<LowQuotaBaseline>,
    observed_cycles: BTreeMap<String, BTreeMap<String, f64>>,
}

impl LowQuotaTracker {
    pub fn reset_baseline(&mut self) {
        self.baseline = None;
    }

    /// Observe successful samples even while notifications are disabled.
    pub fn observe(
        &mut self,
        account: &str,
        windows: &[QuotaWindow],
        threshold: u8,
        now: f64,
    ) -> Vec<QuotaWindow> {
        self.observed_cycles.retain(|_, windows| {
            windows.retain(|_, deadline| *deadline > now);
            !windows.is_empty()
        });
        let previous = self
            .baseline
            .as_ref()
            .filter(|baseline| baseline.account_fingerprint == account);
        let mut current = BTreeMap::new();
        let mut crossed = Vec::new();
        for window in windows {
            let Some(resets_at) = window.resets_at.filter(|deadline| *deadline > now) else {
                continue;
            };
            let remaining = window.remaining();
            if previous
                .and_then(|baseline| baseline.windows.get(&window.id))
                .is_some_and(|old| {
                    old.resets_at == resets_at
                        && old.remaining > f64::from(threshold)
                        && remaining <= f64::from(threshold)
                })
            {
                let observed = self.observed_cycles.entry(account.into()).or_default();
                if observed.get(&window.id) != Some(&resets_at) {
                    observed.insert(window.id.clone(), resets_at);
                    crossed.push(window.clone());
                }
            }
            current.insert(
                window.id.clone(),
                LowQuotaObservation { remaining, resets_at },
            );
        }
        self.baseline = Some(LowQuotaBaseline {
            account_fingerprint: account.into(),
            windows: current,
        });
        crossed
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeadlineReminderState {
    deadline: f64,
    observed_minutes: BTreeSet<u32>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct DeadlineReminderTracker {
    entries: BTreeMap<String, DeadlineReminderState>,
}

impl DeadlineReminderTracker {
    pub fn prune(&mut self, now: f64) {
        self.entries.retain(|_, state| state.deadline > now);
    }

    /// Consume every elapsed stage, returning only the closest stage if it is new.
    /// Call even with notifications disabled so enabling does not replay old stages.
    pub fn observe(
        &mut self,
        key: String,
        deadline: f64,
        now: f64,
        lead_minutes: &[u32],
    ) -> Option<u32> {
        if deadline <= now {
            return None;
        }
        let state = self
            .entries
            .entry(key)
            .or_insert_with(|| DeadlineReminderState {
                deadline,
                observed_minutes: BTreeSet::new(),
            });
        if state.deadline != deadline {
            state.deadline = deadline;
            state.observed_minutes.clear();
        }
        let due = lead_minutes
            .iter()
            .copied()
            .filter(|minutes| deadline - now <= f64::from(*minutes) * 60.0)
            .min()?;
        let is_new = !state.observed_minutes.contains(&due);
        state.observed_minutes.extend(
            lead_minutes
                .iter()
                .copied()
                .filter(|minutes| *minutes >= due),
        );
        is_new.then_some(due)
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct RefreshSchedule {
    pub failures: u32,
    pub next_attempt: f64,
    pub rate_limited_until: f64,
}

impl RefreshSchedule {
    pub fn can_refresh(&self, force: bool, now: f64) -> bool {
        now >= self.rate_limited_until && (force || now >= self.next_attempt)
    }
    pub fn succeeded(&mut self) {
        *self = Self::default();
    }
    pub fn failed(&mut self, retry_after: Option<f64>, now: f64) -> f64 {
        self.failures = self.failures.saturating_add(1);
        let backoff = (30.0 * 2_f64.powi(self.failures.saturating_sub(1).min(4) as i32)).min(300.0);
        let delay = backoff.max(retry_after.unwrap_or(0.0));
        self.next_attempt = now + delay;
        if retry_after.is_some() {
            self.rate_limited_until = self.next_attempt;
        }
        delay
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaPoint {
    pub date: f64,
    pub used_percent: f64,
    pub segment: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuotaSeries {
    pub window: QuotaWindow,
    pub points: Vec<QuotaPoint>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct QuotaHistory {
    pub account_fingerprint: Option<String>,
    pub series: BTreeMap<String, QuotaSeries>,
    pub last_observation: Option<f64>,
}

impl QuotaHistory {
    pub fn observe(
        &mut self,
        account: &str,
        windows: &[QuotaWindow],
        date: f64,
        continuous: bool,
        maximum_gap: f64,
    ) {
        if self.account_fingerprint.as_deref() != Some(account) {
            self.series.clear();
            self.last_observation = None;
            self.account_fingerprint = Some(account.into());
        }
        self.series.retain(|_, series| {
            series
                .points
                .retain(|point| point.date >= date - 7.0 * 86400.0);
            !series.points.is_empty()
        });
        for window in windows {
            let series = self
                .series
                .entry(window.id.clone())
                .or_insert_with(|| QuotaSeries {
                    window: window.clone(),
                    points: Vec::new(),
                });
            let last = series.points.last();
            let connects = last.is_some_and(|point| {
                continuous
                    && Some(point.date) == self.last_observation
                    && date > point.date
                    && date - point.date <= maximum_gap
                    && series.window.resets_at == window.resets_at
                    && window.used_percent >= point.used_percent
            });
            let segment = last.map_or(0, |point| point.segment) + u64::from(!connects);
            let point = QuotaPoint {
                date,
                used_percent: window.used_percent,
                segment,
            };
            let count = series.points.len();
            // 五分钟内只合并同段内部采样，保留重置和中断后的起点。
            if connects
                && count > 1
                && series.points[count - 2].segment == segment
                && (series.points[count - 1].date / 300.0).floor() == (date / 300.0).floor()
            {
                series.points[count - 1] = point;
            } else {
                series.points.push(point);
            }
            series.window = window.clone();
        }
        self.last_observation = Some(date);
    }
}
