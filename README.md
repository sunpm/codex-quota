# Codex Quota

Codex Quota 是支持 Codex 与 Antigravity（反重力）的桌面额度与本地用量分析工具，支持 macOS 和 Windows。

- 查看 Codex 与 Antigravity 的剩余额度和重置倒计时，按服务独立监测。
- 查看 Codex 额度趋势和重置卡，接收额度恢复、额度重置前和重置卡到期提醒。
- 按服务、日期、模型、对话和项目分析 Codex 与 Antigravity Token 用量及估算费用，支持按服务自定义价格。
- 查看用量趋势、缓存命中率、热力图、全局逐条记录与费用拆分。
- 在菜单栏或系统托盘查看额度，关闭窗口后继续监测，退出应用后停止。
- 查看两项服务的 AIHOT 公开重置动态，经确认后安装应用更新。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/usage-dark.png">
  <img src="docs/images/usage.png" alt="用量分析界面：Token、估算费用与用量趋势（离线示例数据）">
</picture>

<details>
<summary>查看额度监测截图</summary>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/quota-dark.png">
  <img src="docs/images/quota.png" alt="额度监测界面：剩余额度、重置倒计时与额度趋势（离线示例数据）">
</picture>

</details>

额度监测复用各自官方 CLI 的登录态，本应用不保存或改写凭据。Antigravity 监测默认关闭，只显示 CLI 返回的额度分组；CLI 报告不提供可靠账号身份，因此不记录 Antigravity 额度历史或发送个人恢复提醒。用量分析可独立使用，只读本机 Codex 日志、Antigravity CLI / 桌面端 JSONL 与 SQLite，以及已确认口径的采集历史，可能包含多个账号。费用按 API 单价估算，**不代表订阅账单**。

[使用说明](docs/usage.md) · [版本历史](CHANGELOG.md) · [反馈问题](https://github.com/sunpm/codex-quota/issues)

[开发与构建](docs/development.md) · [升级与发布](docs/updating.md) · [第三方来源与许可](THIRD_PARTY_NOTICES.md)

## 环境要求

| 项目 | 要求 |
| --- | --- |
| macOS | macOS 13+，Apple Silicon 或 Intel |
| Windows | Windows 10 / 11 x64；缺少 WebView2 Runtime 时，安装器会引导安装 |
| Codex 额度 | 已安装并登录 Codex CLI（命令行工具）；Windows 需原生版本 |
| Antigravity 额度 | 已安装并登录官方 `agy`；macOS 至少 1.1.11，Windows 原生 `agy.exe` 至少 1.4.10，均需正式版；不连接 WSL |
| 用量分析 | Codex `.jsonl` / `.jsonl.zst`；Antigravity 原生 `transcript_full.jsonl` / SQLite。旧加密 `.pb` 未覆盖 |

## 安装

安装包尚未提供 Apple 公证或 Windows 代码签名。macOS 首次打开受阻时，见 [首次打开指引](docs/release-notes.md)。

1. **准备所需 CLI**：Codex 按 [官方指南](https://learn.chatgpt.com/docs/codex/cli) 安装并在终端登录。Antigravity 使用[官方 CLI](https://github.com/google-antigravity/antigravity-cli)，运行 `agy` 完成登录；仅查看本机用量可跳过。
2. **下载安装包**：在 [最新发行版](https://github.com/sunpm/codex-quota/releases/latest) 选择对应系统和芯片的安装包。Mac 芯片类型可在“关于本机”中查看；功能与平台以该版本说明为准。
3. **安装应用**：macOS 打开 DMG，将 **Codex Quota** 拖入“应用程序”；Windows 运行安装器，按提示完成安装。
4. **开始使用**：打开 Codex Quota 查看用量，在“设置”中按需开启 Codex / Antigravity 监测、菜单栏 / 托盘与通知。

Antigravity 桌面界面关闭后，额度查询需要独立 CLI、可用的登录态和网络。Windows 禁止查询进程启动子进程，配置了 MCP 等外部辅助程序时可能查询失败。更多条件见[使用说明](docs/usage.md#antigravity-额度)，实际验收结果与未验收平台见[开发说明](docs/development.md)。

Antigravity 本地扫描覆盖 `~/.gemini/antigravity-cli/` 与 `~/.gemini/antigravity/`，可回溯安装前仍保留的记录，不需要 hook 或保持官方界面运行。重复目录按会话与生成记录去重，后续扫描修正重写步骤。缺少模型或价格时保留 Token、显示未知；旧 `.pb`、不支持格式与无法读取的数据会提示覆盖缺口，不承诺恢复全部历史。详见[数据口径](docs/usage.md#antigravity-本地历史)。
