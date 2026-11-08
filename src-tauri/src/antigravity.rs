use quota_core::{decode_antigravity_usage, AntigravityGroup};
use std::{
    io,
    path::{Path, PathBuf},
    process::{Output, Stdio},
    time::Duration,
};
use tempfile::TempDir;
use tokio::{
    io::{AsyncRead, AsyncReadExt},
    process::{Child, Command},
};

const OUTPUT_LIMIT: usize = 1024 * 1024;

#[derive(Debug)]
pub struct AntigravityError {
    pub message: String,
    pub retry_after: Option<f64>,
    pub requires_action: bool,
}

impl AntigravityError {
    fn new(message: &str, requires_action: bool) -> Self {
        Self {
            message: message.into(),
            retry_after: None,
            requires_action,
        }
    }
}

#[derive(Default)]
pub struct AntigravityClient {
    child: Option<Child>,
    directory: Option<TempDir>,
    #[cfg(unix)]
    process_group: Option<i32>,
    #[cfg(windows)]
    job: Option<std::os::windows::io::OwnedHandle>,
}

impl AntigravityClient {
    pub async fn sample(&mut self) -> Result<Vec<AntigravityGroup>, AntigravityError> {
        let result = self.read_sample().await;
        self.stop().await;
        result
    }

    async fn read_sample(&mut self) -> Result<Vec<AntigravityGroup>, AntigravityError> {
        let executable = locate_executable()?;
        self.directory = Some(prepare_directory()?);
        let version = self
            .run(&executable, &["--version"], Duration::from_secs(3))
            .await?;
        let version = std::str::from_utf8(&version.stdout)
            .ok()
            .and_then(|value| semver::Version::parse(value.trim()).ok())
            .filter(|version| version.pre.is_empty())
            .ok_or_else(|| {
                AntigravityError::new(
                    "无法确认 Antigravity CLI 正式版版本，请更新 agy 后重试。",
                    true,
                )
            })?;
        let required = if cfg!(windows) {
            semver::Version::new(1, 4, 10)
        } else {
            semver::Version::new(1, 1, 11)
        };
        if version < required {
            return Err(AntigravityError::new(
                &format!("需要 Antigravity CLI {required} 或更新正式版，请在终端更新 agy。"),
                true,
            ));
        }
        let output = self
            .run(
                &executable,
                &["-p", "/usage", "--output-format", "json"],
                Duration::from_secs(90),
            )
            .await?;
        decode_antigravity_usage(&output.stdout)
            .map_err(|message| AntigravityError::new(&message, true))
    }

    async fn run(
        &mut self,
        executable: &Path,
        args: &[&str],
        timeout: Duration,
    ) -> Result<Output, AntigravityError> {
        let directory = self.directory.as_ref().unwrap().path();
        let mut command = Command::new(executable);
        command
            .args(args)
            .current_dir(directory)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .env("AGY_CLI_DISABLE_AUTO_UPDATE", "true")
            .env("AGY_CLI_NONINTERACTIVE_HEADLESS", "true")
            .env("AGY_CLI_INTERACTIVE_HEADLESS", "false")
            .env_remove("SSH_CONNECTION")
            .env_remove("SSH_CLIENT")
            .env_remove("SSH_TTY");
        #[cfg(unix)]
        {
            let mut paths = vec![directory.to_path_buf()];
            if let Some(path) = std::env::var_os("PATH") {
                paths.extend(std::env::split_paths(&path));
            }
            command
                .env(
                    "PATH",
                    std::env::join_paths(paths).map_err(|_| {
                        AntigravityError::new("无法准备 Antigravity 后台查询环境。", true)
                    })?,
                )
                .env("BROWSER", directory.join("open"))
                .env(
                    "CODEX_QUOTA_AGY_AUTH_BLOCKED",
                    directory.join("auth-blocked"),
                );
            // A separate session has no controlling terminal and owns its process group.
            unsafe {
                command.pre_exec(|| {
                    if libc::setsid() == -1 {
                        Err(io::Error::last_os_error())
                    } else {
                        Ok(())
                    }
                });
            }
        }
        #[cfg(windows)]
        {
            use windows_sys::Win32::System::Threading::{CREATE_SUSPENDED, DETACHED_PROCESS};
            // CREATE_NO_WINDOW still gives agy a CONIN$ input; detach and contain it before execution.
            command.creation_flags(DETACHED_PROCESS | CREATE_SUSPENDED);
            self.job = Some(create_background_job().map_err(|_| {
                AntigravityError::new("无法建立 Antigravity 后台进程限制，未启动查询。", true)
            })?);
        }
        let mut child = command.spawn().map_err(|_| {
            AntigravityError::new(
                "无法启动 Antigravity CLI，请检查 agy 安装和执行权限。",
                true,
            )
        })?;
        let stdout = child.stdout.take().unwrap();
        let stderr = child.stderr.take().unwrap();
        #[cfg(unix)]
        {
            self.process_group = child.id().map(|pid| pid as i32);
        }
        self.child = Some(child);
        #[cfg(windows)]
        if contain_and_resume(self.job.as_ref().unwrap(), self.child.as_ref().unwrap()).is_err() {
            self.stop_process().await;
            return Err(AntigravityError::new(
                "无法限制 Antigravity 后台子进程，已停止查询。",
                true,
            ));
        }
        let mut output = Vec::new();
        let mut diagnostic = Vec::new();
        let result = tokio::time::timeout(timeout, async {
            tokio::try_join!(
                self.child.as_mut().unwrap().wait(),
                read_output(stdout, &mut output),
                read_output(stderr, &mut diagnostic)
            )
        })
        .await;
        self.stop_process().await;
        let blocked = self
            .directory
            .as_ref()
            .unwrap()
            .path()
            .join("auth-blocked")
            .exists();
        if blocked {
            return Err(AntigravityError::new(
                "Antigravity 需要登录，已阻止后台打开浏览器。请在终端运行 agy 登录后重试。",
                true,
            ));
        }
        match result {
            Ok(Ok((status, (), ()))) if status.success() => Ok(Output {
                status,
                stdout: output,
                stderr: diagnostic,
            }),
            Ok(Ok(_)) => Err(classify_failure(&diagnostic, false)),
            Err(_) => Err(classify_failure(&diagnostic, true)),
            Ok(Err(error)) => Err(AntigravityError::new(
                if error.kind() == io::ErrorKind::InvalidData {
                    "Antigravity CLI 输出过大，已停止查询。请更新 agy 后重试。"
                } else {
                    "无法读取 Antigravity CLI 输出，请在终端确认 agy 可正常运行。"
                },
                true,
            )),
        }
    }

    async fn stop_process(&mut self) {
        #[cfg(unix)]
        if let Some(group) = self.process_group.take() {
            unsafe { libc::kill(-group, libc::SIGKILL) };
        }
        #[cfg(windows)]
        self.job.take();
        if let Some(mut child) = self.child.take() {
            let _ = child.start_kill();
            let _ = child.wait().await;
        }
    }

    pub async fn stop(&mut self) {
        self.stop_process().await;
        self.directory.take();
    }
}

impl Drop for AntigravityClient {
    fn drop(&mut self) {
        #[cfg(unix)]
        if let Some(group) = self.process_group.take() {
            unsafe { libc::kill(-group, libc::SIGKILL) };
        }
        #[cfg(windows)]
        self.job.take();
        if let Some(child) = &mut self.child {
            let _ = child.start_kill();
        }
    }
}

fn locate_executable() -> Result<PathBuf, AntigravityError> {
    if let Some(path) = std::env::var_os("CODEX_QUOTA_AGY") {
        return executable_path(PathBuf::from(path)).ok_or_else(|| {
            AntigravityError::new(
                "CODEX_QUOTA_AGY 未指向可执行的原生 agy，请修正该路径。",
                true,
            )
        });
    }
    let name = if cfg!(windows) { "agy.exe" } else { "agy" };
    let mut candidates = Vec::new();
    if let Some(path) = std::env::var_os("PATH") {
        candidates.extend(std::env::split_paths(&path).map(|path| path.join(name)));
    }
    if let Some(home) = dirs::home_dir() {
        candidates.push(home.join(".local/bin").join(name));
    }
    #[cfg(target_os = "macos")]
    candidates.extend(["/opt/homebrew/bin/agy", "/usr/local/bin/agy"].map(PathBuf::from));
    #[cfg(windows)]
    if let Some(local) = std::env::var_os("LOCALAPPDATA") {
        candidates.push(PathBuf::from(local).join("agy/bin/agy.exe"));
    }
    candidates
        .into_iter()
        .find_map(executable_path)
        .ok_or_else(|| {
            AntigravityError::new(
                "未找到 Antigravity CLI。请先安装并登录 agy；自定义位置可通过 CODEX_QUOTA_AGY 指定。",
                true,
            )
        })
}

fn executable_path(path: PathBuf) -> Option<PathBuf> {
    let metadata = path.metadata().ok()?;
    if !metadata.is_file() {
        return None;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if metadata.permissions().mode() & 0o111 == 0 {
            return None;
        }
    }
    #[cfg(windows)]
    if !path
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| extension.eq_ignore_ascii_case("exe"))
    {
        return None;
    }
    path.canonicalize().ok()
}

fn prepare_directory() -> Result<TempDir, AntigravityError> {
    let directory = tempfile::Builder::new()
        .prefix("codex-quota-agy-")
        .tempdir()
        .map_err(|_| AntigravityError::new("无法创建 Antigravity 查询临时目录。", true))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(directory.path(), std::fs::Permissions::from_mode(0o700))
            .map_err(|_| AntigravityError::new("无法保护 Antigravity 查询临时目录。", true))?;
        for name in ["open", "xdg-open"] {
            let path = directory.path().join(name);
            std::fs::write(
                &path,
                b"#!/bin/sh\n: > \"$CODEX_QUOTA_AGY_AUTH_BLOCKED\"\nexit 1\n",
            )
            .and_then(|()| std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700)))
            .map_err(|_| {
                AntigravityError::new("无法阻止 Antigravity 后台浏览器登录，未启动查询。", true)
            })?;
        }
    }
    Ok(directory)
}

async fn read_output(mut reader: impl AsyncRead + Unpin, bytes: &mut Vec<u8>) -> io::Result<()> {
    let mut buffer = [0u8; 8192];
    loop {
        let count = reader.read(&mut buffer).await?;
        if count == 0 {
            return Ok(());
        }
        if bytes.len() + count > OUTPUT_LIMIT {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "output limit"));
        }
        bytes.extend_from_slice(&buffer[..count]);
    }
}

fn classify_failure(stderr: &[u8], timed_out: bool) -> AntigravityError {
    let diagnostic = String::from_utf8_lossy(stderr);
    let text = diagnostic.to_ascii_lowercase();
    if [
        "http 429",
        "status 429",
        "code: 429",
        "rate limit",
        "too many requests",
    ]
    .iter()
    .any(|marker| text.contains(marker))
    {
        let retry_after = diagnostic.lines().find_map(|line| {
            let (name, value) = line.trim().split_once(':')?;
            if !name.eq_ignore_ascii_case("retry-after") {
                return None;
            }
            value
                .trim()
                .parse::<f64>()
                .ok()
                .or_else(|| {
                    chrono::DateTime::parse_from_rfc2822(value.trim())
                        .ok()
                        .map(|date| (date.timestamp() - chrono::Utc::now().timestamp()) as f64)
                })
                .filter(|seconds| seconds.is_finite() && *seconds >= 0.0)
        });
        return AntigravityError {
            message: "Antigravity 请求受限，稍后重试。".into(),
            retry_after: Some(retry_after.unwrap_or(300.0).max(300.0)),
            requires_action: false,
        };
    }
    // Transient network failures can also make the CLI request sign-in.
    if [
        "network",
        "connection refused",
        "connection reset",
        "no such host",
        "i/o timeout",
        "connection timed out",
        "certificate",
        "dns",
        "tls",
        "proxyconnect",
    ]
    .iter()
    .any(|marker| text.contains(marker))
    {
        return AntigravityError::new("Antigravity 网络连接失败，请检查网络。", false);
    }
    if [
        "authentication required",
        "not logged in",
        "not signed in",
        "please sign in",
        "please log in",
        "invalid_grant",
        "unauthenticated",
    ]
    .iter()
    .any(|marker| text.contains(marker))
    {
        return AntigravityError::new("Antigravity 需要登录，请在终端运行 agy 登录后重试。", true);
    }
    if timed_out {
        AntigravityError::new("读取超时，请在终端确认 agy 登录及网络后重试。", true)
    } else {
        AntigravityError::new(
            "Antigravity CLI 未能返回额度，请在终端确认 agy 登录及网络后重试。",
            true,
        )
    }
}

#[cfg(windows)]
fn create_background_job() -> io::Result<std::os::windows::io::OwnedHandle> {
    use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
    use windows_sys::Win32::System::JobObjects::{
        CreateJobObjectW, JobObjectExtendedLimitInformation, SetInformationJobObject,
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JOB_OBJECT_LIMIT_ACTIVE_PROCESS,
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    };
    let handle = unsafe { CreateJobObjectW(std::ptr::null(), std::ptr::null()) };
    if handle.is_null() {
        return Err(io::Error::last_os_error());
    }
    let job = unsafe { OwnedHandle::from_raw_handle(handle) };
    let mut limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_ACTIVE_PROCESS | JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    limits.BasicLimitInformation.ActiveProcessLimit = 1;
    if unsafe {
        SetInformationJobObject(
            job.as_raw_handle(),
            JobObjectExtendedLimitInformation,
            &limits as *const _ as *const _,
            std::mem::size_of_val(&limits) as u32,
        )
    } == 0
    {
        return Err(io::Error::last_os_error());
    }
    Ok(job)
}

#[cfg(windows)]
fn contain_and_resume(job: &std::os::windows::io::OwnedHandle, child: &Child) -> io::Result<()> {
    use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
    use windows_sys::Win32::{
        Foundation::INVALID_HANDLE_VALUE,
        System::{
            Diagnostics::ToolHelp::{
                CreateToolhelp32Snapshot, Thread32First, Thread32Next, TH32CS_SNAPTHREAD,
                THREADENTRY32,
            },
            JobObjects::AssignProcessToJobObject,
            Threading::{OpenThread, ResumeThread, THREAD_SUSPEND_RESUME},
        },
    };
    if unsafe { AssignProcessToJobObject(job.as_raw_handle(), child.raw_handle().unwrap()) } == 0 {
        return Err(io::Error::last_os_error());
    }
    // std/Tokio exposes the process handle, but closes CreateProcess's primary thread handle.
    // The suspended process has only its initial thread; locate that thread before resuming it.
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0) };
    if snapshot == INVALID_HANDLE_VALUE {
        return Err(io::Error::last_os_error());
    }
    let snapshot = unsafe { OwnedHandle::from_raw_handle(snapshot) };
    let mut entry = THREADENTRY32 {
        dwSize: std::mem::size_of::<THREADENTRY32>() as u32,
        ..Default::default()
    };
    let pid = child.id().unwrap();
    let mut found = unsafe { Thread32First(snapshot.as_raw_handle(), &mut entry) };
    while found != 0 {
        if entry.th32OwnerProcessID == pid {
            let thread = unsafe { OpenThread(THREAD_SUSPEND_RESUME, 0, entry.th32ThreadID) };
            if thread.is_null() {
                return Err(io::Error::last_os_error());
            }
            let thread = unsafe { OwnedHandle::from_raw_handle(thread) };
            return if unsafe { ResumeThread(thread.as_raw_handle()) } == u32::MAX {
                Err(io::Error::last_os_error())
            } else {
                Ok(())
            };
        }
        found = unsafe { Thread32Next(snapshot.as_raw_handle(), &mut entry) };
    }
    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "missing child thread",
    ))
}
