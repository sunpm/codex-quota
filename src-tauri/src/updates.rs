use crate::{
    monitor::controller,
    state::{now, AppSnapshot, SavedState},
};
use serde::Deserialize;
use std::time::Duration;
use tauri::AppHandle;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons};
use tauri_plugin_updater::{Update, UpdaterExt};

pub fn installed_release_notes(app: &AppHandle, saved: &SavedState) -> Option<String> {
    let notes = include_str!(concat!(env!("OUT_DIR"), "/installed-release-notes.md")).trim();
    let version = app.package_info().version.to_string();
    let shown = saved
        .preferences
        .get("updates.lastShownReleaseNotesVersion")
        .and_then(serde_json::Value::as_str);
    (!notes.is_empty() && shown != Some(version.as_str())).then(|| notes.to_string())
}

#[tauri::command]
pub fn mark_release_notes_shown(app: AppHandle) -> Result<AppSnapshot, String> {
    let state = controller(&app);
    let snapshot = {
        let mut store = state.store.lock().unwrap();
        if store.snapshot.installed_release_notes.is_some() {
            let mut saved = store.saved.clone();
            saved.preferences.insert(
                "updates.lastShownReleaseNotesVersion".into(),
                serde_json::json!(store.snapshot.version),
            );
            store.commit(saved)?;
            store.snapshot.installed_release_notes = None;
        }
        store.snapshot.clone()
    };
    state.emit(&app);
    Ok(snapshot)
}

#[derive(Default)]
pub struct UpdateRuntime {
    pub pending: Option<Update>,
    pub checking: Option<tokio::task::AbortHandle>,
    pub downloading: Option<tokio::task::AbortHandle>,
}

pub fn public_key(app: &AppHandle) -> Option<String> {
    app.config()
        .plugins
        .0
        .get("updater")
        .and_then(|v| v.get("pubkey"))
        .and_then(|v| v.as_str())
        .filter(|v| !v.is_empty())
        .map(String::from)
        .or_else(|| {
            option_env!("TAURI_UPDATER_PUBLIC_KEY")
                .filter(|v| !v.is_empty())
                .map(String::from)
        })
}

pub async fn check(app: &AppHandle) -> Result<AppSnapshot, String> {
    let state = controller(app);
    {
        let mut store = state.store.lock().unwrap();
        if ["checking", "downloading", "installing"]
            .contains(&store.snapshot.update.status.as_str())
        {
            return Ok(store.snapshot.clone());
        }
        if state.preview {
            return Err("离线预览不检查更新。".into());
        }
        store.snapshot.update.status = "checking".into();
        store.snapshot.update.error = None;
        store.saved.next_update_check = now() + 86400.0;
        let _ = store.persist();
    }
    state.emit(app);
    let handle = app.clone();
    let task = tokio::spawn(async move {
        let public_key = public_key(&handle);
        if let Some(key) = &public_key {
            let builder = handle
                .updater_builder()
                .pubkey(key.clone())
                .timeout(Duration::from_secs(25));
            #[cfg(all(target_os = "macos", target_arch = "x86_64"))]
            let builder = if std::process::Command::new("/usr/sbin/sysctl")
                .args(["-in", "sysctl.proc_translated"])
                .output()
                .is_ok_and(|output| output.status.success() && output.stdout.starts_with(b"1"))
            {
                builder.target("darwin-aarch64")
            } else {
                builder
            };
            let updater = builder.build().map_err(|_| "更新配置不可用。")?;
            match updater.check().await {
                Ok(update) => {
                    return Ok(update
                        .map(|update| (update.version.clone(), update.body.clone(), Some(update))))
                }
                // The latest stable release can still be a Sparkle release without latest.json.
                Err(tauri_plugin_updater::Error::ReleaseNotFound) => {}
                Err(error) => return Err(format!("无法检查更新：{error}")),
            }
        }
        {
            #[derive(Deserialize)]
            struct Release {
                tag_name: String,
                body: Option<String>,
                prerelease: bool,
                draft: bool,
                assets: Vec<Asset>,
            }
            #[derive(Deserialize)]
            struct Asset {
                name: String,
            }
            let response = controller(&handle)
                .http
                .get("https://api.github.com/repos/sunpm/codex-quota/releases/latest")
                .send()
                .await
                .map_err(|_| "无法读取发布信息，请稍后重试。")?
                .error_for_status()
                .map_err(|_| "发布信息暂不可用，请打开发布页。")?;
            let release: Release = response.json().await.map_err(|_| "发布信息格式不兼容。")?;
            if public_key.is_some()
                && release
                    .assets
                    .iter()
                    .any(|asset| asset.name == "latest.json")
            {
                return Err("更新清单暂不可用，请稍后重试或打开发布页。".into());
            }
            let version = semver::Version::parse(release.tag_name.trim_start_matches('v'))
                .map_err(|_| "发布版本格式不兼容。")?;
            if !release.draft && !release.prerelease && version > handle.package_info().version {
                Ok(Some((version.to_string(), release.body, None)))
            } else {
                Ok(None)
            }
        }
    });
    state.updates.lock().unwrap().checking = Some(task.abort_handle());
    let result = task.await;
    state.updates.lock().unwrap().checking = None;
    {
        let mut store = state.store.lock().unwrap();
        match result {
            Ok(Ok(Some((version, notes, update)))) => {
                store.snapshot.update.status = "available".into();
                store.snapshot.update.version = Some(version);
                store.snapshot.update.notes = notes;
                store.snapshot.update.can_install = update.is_some();
                state.updates.lock().unwrap().pending = update;
            }
            Ok(Ok(None)) => {
                store.snapshot.update.status = "current".into();
                store.snapshot.update.version = None;
                store.snapshot.update.notes = None;
                store.snapshot.update.can_install = false;
                state.updates.lock().unwrap().pending = None;
            }
            Ok(Err(error)) => {
                store.snapshot.update.status = "error".into();
                store.snapshot.update.error = Some(error);
            }
            Err(error) if error.is_cancelled() => {
                store.snapshot.update.status = "idle".into();
            }
            Err(_) => {
                store.snapshot.update.status = "error".into();
                store.snapshot.update.error = Some("更新检查未完成，请重试。".into());
            }
        }
    }
    state.emit(app);
    let snapshot = state.store.lock().unwrap().snapshot.clone();
    Ok(snapshot)
}

pub fn cancel_check(app: &AppHandle) {
    if let Some(task) = controller(app).updates.lock().unwrap().checking.take() {
        task.abort();
    }
}

pub async fn install(app: &AppHandle) -> Result<AppSnapshot, String> {
    let state = controller(app);
    let update = state
        .updates
        .lock()
        .unwrap()
        .pending
        .clone()
        .ok_or("没有可安装的已验证更新，请先检查更新。")?;
    {
        let store = state.store.lock().unwrap();
        if ["downloading", "installing"].contains(&store.snapshot.update.status.as_str()) {
            return Ok(store.snapshot.clone());
        }
    }
    let confirmed = app
        .dialog()
        .message(format!(
            "下载并安装 {}，完成后将重新打开 Codex Quota。",
            update.version
        ))
        .title("安装更新")
        .buttons(MessageDialogButtons::OkCancelCustom(
            "安装并重启".into(),
            "取消".into(),
        ))
        .blocking_show();
    if !confirmed {
        return Ok(state.store.lock().unwrap().snapshot.clone());
    }
    {
        let mut store = state.store.lock().unwrap();
        store.snapshot.update.status = "downloading".into();
        store.snapshot.update.progress = Some(0.0);
        store.snapshot.update.error = None;
    }
    state.emit(app);
    let handle = app.clone();
    let task = tokio::spawn(async move {
        let mut downloaded = 0_u64;
        let bytes = update
            .download(
                |chunk, total| {
                    downloaded += chunk as u64;
                    let state = controller(&handle);
                    state.store.lock().unwrap().snapshot.update.progress = total
                        .filter(|n| *n > 0)
                        .map(|total| downloaded as f64 / total as f64 * 100.0);
                    state.emit(&handle);
                },
                || {},
            )
            .await
            .map_err(|_| "更新下载或签名验证失败，请重试。")?;
        let state = controller(&handle);
        state.store.lock().unwrap().snapshot.update.status = "installing".into();
        state.emit(&handle);
        state.active.send_replace(false);
        state.client.lock().await.stop().await;
        tauri::async_runtime::spawn_blocking(move || update.install(bytes))
            .await
            .map_err(|_| "安装更新未完成。")?
            .map_err(|_| "安装更新失败，请重试或从发布页手动安装。")?;
        handle.restart();
        #[allow(unreachable_code)]
        Ok::<(), String>(())
    });
    state.updates.lock().unwrap().downloading = Some(task.abort_handle());
    let result = task.await;
    state.updates.lock().unwrap().downloading = None;
    {
        let mut store = state.store.lock().unwrap();
        match result {
            Ok(Ok(())) => {}
            Err(error) if error.is_cancelled() => {
                store.snapshot.update.status = "available".into();
                store.snapshot.update.progress = None;
            }
            result => {
                let error = match result {
                    Ok(Err(error)) => error,
                    _ => "更新未完成，请重试。".into(),
                };
                store.snapshot.update.status = "error".into();
                store.snapshot.update.error = Some(error);
                state.active.send_replace(
                    store.snapshot.settings.monitoring_enabled
                        && !state.paused.load(std::sync::atomic::Ordering::Relaxed),
                );
            }
        }
    }
    state.emit(app);
    let snapshot = state.store.lock().unwrap().snapshot.clone();
    Ok(snapshot)
}

pub fn cancel(app: &AppHandle) -> AppSnapshot {
    let state = controller(app);
    let status = state.store.lock().unwrap().snapshot.update.status.clone();
    if status == "checking" {
        cancel_check(app);
    }
    if status == "downloading" {
        if let Some(task) = state.updates.lock().unwrap().downloading.take() {
            task.abort();
        }
    }
    let snapshot = state.store.lock().unwrap().snapshot.clone();
    snapshot
}
