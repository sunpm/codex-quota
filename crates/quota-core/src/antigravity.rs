use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AntigravityGroup {
    pub name: String,
    pub buckets: Vec<AntigravityBucket>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AntigravityBucket {
    pub id: String,
    pub name: String,
    pub window: Option<String>,
    pub remaining_percent: Option<f64>,
    pub resets_at: Option<f64>,
    pub disabled: bool,
}

#[derive(Deserialize)]
struct Report {
    status: String,
    command: UsageCommand,
}

#[derive(Deserialize)]
struct UsageCommand {
    name: String,
    data: UsageData,
}

#[derive(Deserialize)]
struct UsageData {
    groups: Vec<RawGroup>,
}

#[derive(Deserialize)]
struct RawGroup {
    name: String,
    buckets: Vec<RawBucket>,
}

#[derive(Deserialize)]
struct RawBucket {
    id: String,
    name: Option<String>,
    window: Option<String>,
    #[serde(default)]
    remaining_fraction: Value,
    #[serde(default)]
    reset_time: Value,
    #[serde(default)]
    disabled: bool,
}

pub fn decode_antigravity_usage(bytes: &[u8]) -> Result<Vec<AntigravityGroup>, String> {
    let report: Report = serde_json::from_slice(bytes)
        .map_err(|_| "Antigravity CLI 额度报告格式暂不兼容，请检查 CLI 版本。")?;
    if report.status != "SUCCESS" || report.command.name != "usage" {
        return Err("Antigravity CLI 未返回成功的 usage 报告。".into());
    }
    if report.command.data.groups.is_empty() {
        return Err("Antigravity CLI 未返回额度分组。".into());
    }
    report
        .command
        .data
        .groups
        .into_iter()
        .map(|group| {
            let mut ids = BTreeSet::new();
            if group.name.trim().is_empty()
                || group.buckets.is_empty()
                || group
                    .buckets
                    .iter()
                    .any(|bucket| bucket.id.trim().is_empty() || !ids.insert(&bucket.id))
            {
                return Err("Antigravity CLI 额度分组或桶 ID 不完整。".into());
            }
            Ok(AntigravityGroup {
                name: group.name,
                buckets: group
                    .buckets
                    .into_iter()
                    .map(|bucket| {
                        let remaining_percent = bucket
                            .remaining_fraction
                            .as_f64()
                            .filter(|fraction| {
                                !bucket.disabled
                                    && fraction.is_finite()
                                    && (0.0..=1.0).contains(fraction)
                            })
                            .map(|fraction| fraction * 100.0);
                        AntigravityBucket {
                            name: bucket
                                .name
                                .filter(|name| !name.trim().is_empty())
                                .unwrap_or_else(|| bucket.id.clone()),
                            id: bucket.id,
                            window: bucket.window,
                            remaining_percent,
                            resets_at: bucket.reset_time.as_str().and_then(crate::parse_timestamp),
                            disabled: bucket.disabled,
                        }
                    })
                    .collect(),
            })
        })
        .collect()
}
