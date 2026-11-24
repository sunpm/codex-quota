use quota_core::{AntigravityBucket, AntigravityGroup};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Element {
    Heading(String),
    Text(String),
}

pub async fn read() -> Result<Option<Vec<AntigravityGroup>>, String> {
    let Some(json) = panel_contents().await? else {
        return Ok(None);
    };
    let elements: Vec<Element> =
        serde_json::from_slice(&json).map_err(|_| "无法识别 Antigravity 桌面额度面板。")?;
    let mut groups = Vec::new();
    let mut group: Option<AntigravityGroup> = None;
    let mut waiting_for_percent = false;
    for element in elements {
        match element {
            Element::Heading(name) => {
                groups.extend(group.take().filter(|g| !g.buckets.is_empty()));
                group = Some(AntigravityGroup {
                    name,
                    buckets: Vec::new(),
                });
                waiting_for_percent = false;
            }
            Element::Text(text) => {
                let Some(group) = &mut group else { continue };
                let text = text.trim();
                if let Some(value) = text.strip_suffix('%').or_else(|| text.strip_suffix('％')) {
                    if waiting_for_percent {
                        group.buckets.last_mut().unwrap().remaining_percent = value
                            .trim()
                            .parse::<f64>()
                            .ok()
                            .filter(|value| (0.0..=100.0).contains(value));
                        waiting_for_percent = false;
                    }
                    continue;
                }
                let label = text.to_lowercase().replace('-', " ");
                // The panel's quota rows have a bucket label, optional reset text, then a visible percentage.
                if !(label.ends_with("limit")
                    || label.ends_with("limit remaining")
                    || label.ends_with("quota remaining")
                    || label.ends_with("额度")
                    || label.ends_with("限额"))
                    || label.contains("已用")
                {
                    if !label.starts_with("refresh")
                        && !label.starts_with("reset")
                        && !label.contains("重置")
                        && !label.contains("刷新")
                    {
                        waiting_for_percent = false;
                    }
                    continue;
                }
                let window = if label.contains("weekly")
                    || label.contains("每周")
                    || label.contains("周额度")
                {
                    Some("weekly")
                } else if label.contains("five hour")
                    || label.contains("5 hour")
                    || label.contains("5h")
                    || label.contains("五小时")
                    || label.contains("5 小时")
                {
                    Some("5h")
                } else {
                    None
                };
                group.buckets.push(AntigravityBucket {
                    id: text.into(),
                    name: text.into(),
                    window: window.map(str::to_owned),
                    remaining_percent: None,
                    resets_at: None,
                    disabled: false,
                });
                waiting_for_percent = true;
            }
        }
    }
    groups.extend(group.filter(|g| !g.buckets.is_empty()));
    if groups.is_empty() {
        return Err("桌面面板尚未显示可识别的模型额度。".into());
    }
    Ok(Some(groups))
}

#[cfg(target_os = "macos")]
async fn panel_contents() -> Result<Option<Vec<u8>>, String> {
    use std::ffi::{c_char, CStr};
    extern "C" {
        fn cq_read_antigravity_panel(json: *mut *mut c_char) -> i32;
    }
    tokio::task::spawn_blocking(|| {
        let mut json = std::ptr::null_mut();
        match unsafe { cq_read_antigravity_panel(&mut json) } {
            0 => unsafe {
                let bytes = CStr::from_ptr(json).to_bytes().to_vec();
                libc::free(json.cast());
                Ok(Some(bytes))
            },
            1 => Err(
                "请在系统设置「隐私与安全性 → 辅助功能」中允许 Codex Quota 读取桌面额度面板。"
                    .into(),
            ),
            2 => Ok(None),
            _ => Err("无法读取 Antigravity 桌面额度面板。".into()),
        }
    })
    .await
    .map_err(|_| "读取 Antigravity 桌面额度面板中断。")?
}

#[cfg(windows)]
async fn panel_contents() -> Result<Option<Vec<u8>>, String> {
    use std::{process::Stdio, time::Duration};
    use tokio::process::Command;
    let system = std::env::var_os("SystemRoot").ok_or("无法定位 Windows PowerShell。")?;
    let shell =
        std::path::PathBuf::from(system).join(r"System32\WindowsPowerShell\v1.0\powershell.exe");
    let mut command = Command::new(shell);
    command
        .creation_flags(0x08000000)
        .kill_on_drop(true)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .args([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            include_str!("antigravity_panel.ps1"),
        ]);
    let output = tokio::time::timeout(Duration::from_secs(12), command.output())
        .await
        .map_err(|_| "读取 Antigravity 桌面额度面板超时。")?
        .map_err(|_| "无法启动 Windows 辅助功能读取器。")?;
    match output.status.code() {
        Some(0) => Ok(Some(output.stdout)),
        Some(2) => Ok(None),
        _ => Err("无法读取 Antigravity 桌面额度面板。".into()),
    }
}

#[cfg(not(any(windows, target_os = "macos")))]
async fn panel_contents() -> Result<Option<Vec<u8>>, String> {
    Err("此平台不支持读取 Antigravity 桌面额度面板。".into())
}
