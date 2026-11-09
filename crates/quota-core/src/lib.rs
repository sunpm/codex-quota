mod announcements;
mod antigravity;
mod antigravity_usage;
mod pricing;
mod official_pricing;
mod project;
mod quota;
mod usage;

pub use announcements::*;
pub use antigravity::*;
pub use pricing::*;
pub use official_pricing::*;
pub use quota::*;
pub use rust_decimal::Decimal;
pub use usage::*;

pub const SWIFT_EPOCH_OFFSET: f64 = 978_307_200.0;

pub fn parse_timestamp(value: &str) -> Option<f64> {
    chrono::DateTime::parse_from_rfc3339(value)
        .ok()
        .map(|date| {
            date.timestamp() as f64 + f64::from(date.timestamp_subsec_nanos()) / 1_000_000_000.0
        })
}

pub fn write_json_atomic(
    path: &std::path::Path,
    value: &impl serde::Serialize,
) -> Result<(), String> {
    let parent = path.parent().ok_or("保存目录无效")?;
    std::fs::create_dir_all(parent).map_err(|_| "无法创建保存目录")?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|_| "无法创建保存文件")?;
    serde_json::to_writer(file.as_file_mut(), value).map_err(|_| "无法写入保存文件")?;
    file.persist(path).map_err(|_| "无法替换保存文件")?;
    Ok(())
}
