# Codex Quota

Codex Quota 是面向 OpenAI Codex 用户的桌面额度与用量工具，支持 macOS 和 Windows。

- 查看剩余额度、重置倒计时、额度趋势和重置卡到期时间。
- 接收额度恢复、额度重置前和重置卡到期提醒。
- 按日期、模型、对话和项目分析 Token 用量与估算费用，支持自定义价格。
- 查看用量趋势、缓存命中率、热力图和逐条明细。
- 在菜单栏或系统托盘查看额度，关闭窗口后继续监测，退出应用后停止。
- 查看公开重置动态，经确认后安装应用更新。

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

额度监测复用 Codex 登录态，不保存或改写凭据。用量分析可独立使用，读取本机日志与已采集历史，可能包含多个账号。费用按 API 单价估算，**不代表订阅账单**。

[使用说明](docs/usage.md) · [版本历史](CHANGELOG.md) · [反馈问题](https://github.com/sunpm/codex-quota/issues)

[开发与构建](docs/development.md) · [升级与发布](docs/updating.md) · [第三方来源与许可](THIRD_PARTY_NOTICES.md)

## 环境要求

| 项目 | 要求 |
| --- | --- |
| macOS | macOS 13+，Apple Silicon 或 Intel |
| Windows | Windows 10 / 11 x64；缺少 WebView2 Runtime 时，安装器会引导安装 |
| 额度监测 | 已安装并登录 Codex CLI（命令行工具）；Windows 需原生版本，暂不自动连接 WSL |
| 用量分析 | 本机 Codex 会话日志，支持 `.jsonl` 和 `.jsonl.zst` |

## 安装

安装包尚未提供 Apple 公证或 Windows 代码签名。macOS 首次打开受阻时，见 [首次打开指引](docs/release-notes.md)。

1. **准备 Codex CLI**：如需额度监测，按 [官方指南](https://learn.chatgpt.com/docs/codex/cli) 安装，在终端运行 `codex` 并登录。仅查看本机用量可跳过。
2. **下载安装包**：在 [最新发行版](https://github.com/sunpm/codex-quota/releases/latest) 选择对应系统和芯片的安装包。Mac 芯片类型可在“关于本机”中查看；功能与平台以该版本说明为准。
3. **安装应用**：macOS 打开 DMG，将 **Codex Quota** 拖入“应用程序”；Windows 运行安装器，按提示完成安装。
4. **开始使用**：打开 Codex Quota 查看用量，在“设置”中按需开启额度监测和提醒，并允许系统通知。
