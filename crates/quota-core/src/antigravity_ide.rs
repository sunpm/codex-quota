use crate::{
    antigravity_usage::{open_snapshot_db, Timestamp},
    AntigravityBucket, AntigravityGroup,
};
use base64::{engine::general_purpose::STANDARD, Engine};
use prost::Message;
use rusqlite::OptionalExtension;
use std::{collections::HashMap, path::Path};

// The IDE stores a base64 Topic containing a second base64-encoded UserStatus.
#[derive(Clone, PartialEq, Message)]
struct Topic {
    #[prost(map = "string, message", tag = "1")]
    data: HashMap<String, Row>,
}

#[derive(Clone, PartialEq, Message)]
struct Row {
    #[prost(string, tag = "1")]
    value: String,
}

#[derive(Clone, PartialEq, Message)]
struct UserStatus {
    #[prost(message, optional, tag = "33")]
    models: Option<ModelConfigs>,
}

#[derive(Clone, PartialEq, Message)]
struct ModelConfigs {
    #[prost(message, repeated, tag = "1")]
    models: Vec<Model>,
}

#[derive(Clone, PartialEq, Message)]
struct Model {
    #[prost(string, tag = "1")]
    label: String,
    #[prost(message, optional, tag = "15")]
    quota: Option<Quota>,
}

#[derive(Clone, PartialEq, Message)]
struct Quota {
    #[prost(float, optional, tag = "1")]
    remaining_fraction: Option<f32>,
    #[prost(message, optional, tag = "2")]
    reset_time: Option<Timestamp>,
}

pub fn read_antigravity_ide_quota(app_data: &Path) -> Result<Vec<AntigravityGroup>, String> {
    for product in ["Antigravity IDE", "Antigravity"] {
        let path = app_data
            .join(product)
            .join("User/globalStorage/state.vscdb");
        if !path
            .try_exists()
            .map_err(|_| "无法访问 Antigravity IDE 状态目录。")?
        {
            continue;
        }
        let has_wal = path
            .with_file_name("state.vscdb-wal")
            .try_exists()
            .map_err(|_| "无法访问 Antigravity IDE 数据库。")?;
        let db = open_snapshot_db(&path, !has_wal)
            .map_err(|_| "无法打开 Antigravity IDE 的本地额度快照。")?;
        let encoded: Option<Vec<u8>> = db
            .query_row(
                "SELECT CAST(value AS BLOB) FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus'",
                [],
                |row| row.get(0),
            )
            .optional()
            .map_err(|_| "无法读取 Antigravity IDE 的本地额度快照。")?;
        // A current IDE database is authoritative even if it has not synced yet.
        return decode_snapshot(&encoded.ok_or("Antigravity IDE 尚未同步额度。")?);
    }
    Err("未找到 Antigravity IDE 的本地额度快照，请打开 IDE 并登录。".into())
}

fn decode_snapshot(encoded: &[u8]) -> Result<Vec<AntigravityGroup>, String> {
    const INVALID: &str = "Antigravity IDE 额度快照格式暂不兼容。";
    let bytes = STANDARD.decode(encoded).map_err(|_| INVALID)?;
    let topic = Topic::decode(bytes.as_slice()).map_err(|_| INVALID)?;
    let row = topic
        .data
        .get("userStatusSentinelKey")
        .ok_or("Antigravity IDE 尚未同步额度。")?;
    let bytes = STANDARD.decode(&row.value).map_err(|_| INVALID)?;
    let status = UserStatus::decode(bytes.as_slice()).map_err(|_| INVALID)?;
    let mut buckets = Vec::new();
    for model in status.models.unwrap_or_default().models {
        let Some(quota) = model.quota else { continue };
        if model.label.trim().is_empty() {
            return Err(INVALID.into());
        }
        buckets.push(AntigravityBucket {
            id: model.label.clone(),
            name: model.label,
            window: None,
            remaining_percent: quota
                .remaining_fraction
                .filter(|value| (0.0..=1.0).contains(value))
                .map(|fraction| f64::from(fraction * 100.0)),
            resets_at: quota
                .reset_time
                .and_then(|time| time.seconds())
                .filter(|time| *time > 0.0),
            disabled: false,
        });
    }
    if buckets.is_empty() {
        return Err("Antigravity IDE 尚未同步模型额度。".into());
    }
    Ok(vec![AntigravityGroup {
        name: "IDE 本地快照".into(),
        buckets,
    }])
}
