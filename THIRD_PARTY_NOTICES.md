# 第三方来源

本项目的菜单栏模板图像、紧凑额度面板、部分尺寸与颜色以及 Codex SVG 图标，改编自 [nanvon/cc-bar](https://github.com/nanvon/cc-bar)，参考版本 `6d990a2c3c50e8d404ea4d9982c651ce3c544baa`。

参考文件：

- `MenuBar/MenuBarLabel.swift`
- `MenuBar/PopoverRootView.swift`
- `Main/DesignSystem.swift`
- `Resources/Logos/codex.svg`

Copyright (c) 2026 nanvon。采用 MIT License；完整声明保存在 `Resources/ThirdPartyNotices/cc-bar-LICENSE.txt`，构建时一并复制到应用包中。

本次多服务接入还参考了 cc-bar 的 `Core/Credentials/ClaudeAuth.swift`、`CursorAuth.swift` 和 `Core/Quota/ClaudeQuotaClient.swift`、`CursorQuotaClient.swift` 的登录存储格式、解析及 Cursor 解密方式。`AGENTS.md` 吸收了适用于本项目的协作规则，未引入其自动发版约定。

Antigravity 本地进程发现、接口格式及响应解析参考 [steipete/CodexBar](https://github.com/steipete/CodexBar) 的 `Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift`、`AntigravityStatusProbe+ResponseModels.swift`、`AntigravityQuotaSummaryParser.swift` 和 `AntigravityLocalhostSession.swift`。参考日期：2026-10-25。

Copyright (c) 2026 Peter Steinberger。采用 MIT License；完整声明保存在 `Resources/ThirdPartyNotices/CodexBar-LICENSE.txt`，构建时一并复制到应用包中。

本项目继续使用 Codex App Server 复用 Codex 登录，并保留自身的额度恢复通知判定。未引入外部项目的凭据刷新、日志扫描、费用统计或更新服务。
