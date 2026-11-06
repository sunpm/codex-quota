use quota_core::{LimitsResponse, QuotaWindow, RateLimitResetCredits};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{path::PathBuf, process::Stdio, time::Duration};
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    process::{Child, ChildStdin, ChildStdout, Command},
};

pub struct Sample {
    pub fingerprint: String,
    pub windows: Vec<QuotaWindow>,
    pub reset_credits: Option<RateLimitResetCredits>,
}

#[derive(Debug)]
pub struct ClientError {
    pub message: String,
    pub retry_after: Option<f64>,
}

impl ClientError {
    fn new(message: &str) -> Self {
        Self {
            message: message.into(),
            retry_after: None,
        }
    }
}

#[derive(Deserialize)]
struct AccountResponse {
    account: Option<Account>,
}
#[derive(Deserialize)]
struct Account {
    r#type: String,
    email: Option<String>,
}
#[derive(Deserialize)]
struct Response {
    id: Option<u64>,
    result: Option<Value>,
    error: Option<RpcError>,
}
#[derive(Deserialize)]
struct RpcError {
    code: i64,
    data: Option<Value>,
}

#[derive(Default)]
pub struct CodexClient {
    child: Option<Child>,
    input: Option<ChildStdin>,
    output: Option<BufReader<ChildStdout>>,
    next_id: u64,
}

pub fn fingerprint(value: &str) -> String {
    format!("{:x}", Sha256::digest(value.as_bytes()))
}

pub fn locate_executable() -> Result<PathBuf, ClientError> {
    let mut candidates = Vec::new();
    if let Some(path) = std::env::var_os("CODEX_QUOTA_CLI") {
        candidates.push(PathBuf::from(path));
    }
    #[cfg(target_os = "macos")]
    candidates.extend([
        "/Applications/Codex.app/Contents/Resources/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
    ].map(PathBuf::from));
    let name = if cfg!(windows) { "codex.exe" } else { "codex" };
    if let Some(path) = std::env::var_os("PATH") {
        candidates.extend(std::env::split_paths(&path).map(|p| p.join(name)));
    }
    if let Some(home) = dirs::home_dir() {
        candidates.push(home.join(".local/bin").join(name));
        candidates.push(home.join(".cargo/bin").join(name));
    }
    #[cfg(windows)]
    {
        // npm's .cmd launcher needs a console; prefer its actual native executable.
        let mut npm_roots = Vec::new();
        if let Some(root) = std::env::var_os("APPDATA") {
            npm_roots.push(PathBuf::from(root).join("npm"));
        }
        if let Some(path) = std::env::var_os("PATH") {
            npm_roots.extend(std::env::split_paths(&path));
        }
        for root in npm_roots {
            for package in [
                "@openai/codex",
                "@openai/codex-win32-x64",
                "@openai/codex-win32-arm64",
            ] {
                for target in ["x86_64-pc-windows-msvc", "aarch64-pc-windows-msvc"] {
                    candidates.push(
                        root.join("node_modules")
                            .join(package)
                            .join("vendor")
                            .join(target)
                            .join("codex/codex.exe"),
                    );
                    candidates.push(
                        root.join("node_modules/@openai/codex/node_modules")
                            .join(package)
                            .join("vendor")
                            .join(target)
                            .join("codex/codex.exe"),
                    );
                }
            }
        }
    }
    candidates
        .into_iter()
        .find(|p| {
            if !p.is_file() {
                return false;
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                p.metadata()
                    .is_ok_and(|m| m.permissions().mode() & 0o111 != 0)
            }
            #[cfg(not(unix))]
            {
                true
            }
        })
        .ok_or_else(|| {
            ClientError::new(
                "未找到 Codex CLI。请先安装并登录 Codex；自定义位置可通过 CODEX_QUOTA_CLI 指定。",
            )
        })
}

impl CodexClient {
    pub async fn sample(&mut self) -> Result<Sample, ClientError> {
        let result = tokio::time::timeout(Duration::from_secs(20), self.read_sample())
            .await
            .unwrap_or_else(|_| Err(ClientError::new("读取额度超时，将在下次刷新时重连。")));
        if result.is_err() {
            self.stop().await;
        }
        result
    }

    async fn read_sample(&mut self) -> Result<Sample, ClientError> {
        if self.child.is_none() {
            self.connect().await?;
        }
        let account: AccountResponse = serde_json::from_value(
            self.request("account/read", json!({"refreshToken": false}))
                .await?,
        )
        .map_err(|_| ClientError::new("Codex 登录响应格式暂不兼容。"))?;
        let account = account
            .account
            .filter(|a| a.r#type == "chatgpt")
            .ok_or_else(|| ClientError::new("未检测到 ChatGPT 登录。请在 Codex 中登录后重试。"))?;
        let limits: LimitsResponse =
            serde_json::from_value(self.request("account/rateLimits/read", json!({})).await?)
                .map_err(|_| ClientError::new("Codex 额度响应格式暂不兼容。"))?;
        let windows = limits.windows();
        if windows.is_empty() && limits.rate_limit_reset_credits.is_none() {
            return Err(ClientError::new("当前账号没有返回可用的额度数据。"));
        }
        let identity = limits
            .account_id
            .or(account.email)
            .filter(|v| !v.is_empty())
            .ok_or_else(|| ClientError::new("无法识别当前账号，暂时不能比较额度变化。"))?;
        Ok(Sample {
            fingerprint: fingerprint(&identity),
            windows,
            reset_credits: limits.rate_limit_reset_credits,
        })
    }

    async fn connect(&mut self) -> Result<(), ClientError> {
        let mut command = Command::new(locate_executable()?);
        command
            .args(["app-server", "--listen", "stdio://"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .current_dir(std::env::temp_dir())
            .kill_on_drop(true);
        #[cfg(windows)]
        command.creation_flags(0x08000000); // CREATE_NO_WINDOW: a background reader must not open a console.
        let mut child = command
            .spawn()
            .map_err(|_| ClientError::new("无法启动 Codex CLI，请检查安装和执行权限。"))?;
        self.input = child.stdin.take();
        self.output = child.stdout.take().map(BufReader::new);
        self.child = Some(child);
        self.request("initialize", json!({"clientInfo": {"name":"codex_quota", "title":"Codex Quota", "version":env!("CARGO_PKG_VERSION")}})).await?;
        self.send(json!({"method":"initialized", "params":{}}))
            .await
    }

    async fn send(&mut self, value: Value) -> Result<(), ClientError> {
        let mut bytes =
            serde_json::to_vec(&value).map_err(|_| ClientError::new("无法编码 Codex 请求。"))?;
        bytes.push(b'\n');
        self.input
            .as_mut()
            .ok_or_else(|| ClientError::new("Codex 尚未连接。"))?
            .write_all(&bytes)
            .await
            .map_err(|_| ClientError::new("Codex 连接已断开。"))
    }

    async fn request(&mut self, method: &str, params: Value) -> Result<Value, ClientError> {
        self.next_id += 1;
        let id = self.next_id;
        self.send(json!({"id":id,"method":method,"params":params}))
            .await?;
        loop {
            let mut line = String::new();
            let count = self
                .output
                .as_mut()
                .ok_or_else(|| ClientError::new("Codex 尚未连接。"))?
                .read_line(&mut line)
                .await
                .map_err(|_| ClientError::new("无法读取 Codex 响应。"))?;
            if count == 0 {
                return Err(ClientError::new("Codex 进程已退出，将在下次刷新时重连。"));
            }
            let response: Response = serde_json::from_str(&line)
                .map_err(|_| ClientError::new("Codex 响应格式暂不兼容。"))?;
            if response.id != Some(id) {
                continue;
            }
            if let Some(error) = response.error {
                let data = error.data.as_ref();
                let status = data
                    .and_then(|v| v.get("httpStatusCode").or_else(|| v.get("statusCode")))
                    .and_then(Value::as_i64);
                let retry_after = data
                    .and_then(|v| v.get("retryAfter").or_else(|| v.get("retry_after")))
                    .and_then(|v| {
                        v.as_f64().or_else(|| {
                            v.as_str().and_then(|s| {
                                s.parse().ok().or_else(|| {
                                    chrono::DateTime::parse_from_rfc2822(s)
                                        .ok()
                                        .map(|date| date.timestamp() as f64 - crate::state::now())
                                })
                            })
                        })
                    })
                    .filter(|v| v.is_finite() && *v >= 0.0);
                let limited = error.code == 429 || status == Some(429);
                return Err(ClientError {
                    message: if limited {
                        "服务请求过于频繁，等待限流冷却。".into()
                    } else {
                        format!(
                            "Codex 额度请求失败（{}），请确认登录和网络状态。",
                            error.code
                        )
                    },
                    retry_after: if limited {
                        Some(retry_after.unwrap_or(60.0))
                    } else {
                        retry_after
                    },
                });
            }
            return response
                .result
                .ok_or_else(|| ClientError::new("Codex 未返回有效结果。"));
        }
    }

    pub async fn stop(&mut self) {
        self.input = None;
        self.output = None;
        if let Some(mut child) = self.child.take() {
            let _ = child.kill().await;
            let _ = child.wait().await;
        }
    }
}
