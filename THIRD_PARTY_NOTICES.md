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

本项目继续使用 Codex App Server 复用 Codex 登录，并保留自身的额度恢复通知判定。未引入外部项目的凭据刷新或应用更新服务。

主窗口、侧栏菜单及设置分组的视觉层级参考 [cc-switch v4 主界面](https://github.com/farion1231/cc-switch/blob/main/assets/release-notes/v4.0.0/main-zh.png)、[用量页面](https://github.com/farion1231/cc-switch/blob/main/assets/release-notes/v4.0.0/usage-zh.png) 与 `src/index.css` 的中性色分层（参考日期：2026-10-28）。使用本项目的 SwiftUI / AppKit 控件实现，未复制其前端组件或加入依赖；沿用下文的 cc-switch MIT 许可声明。

用量热力图参考上述用量页面的 53 周日历布局，以及 [PR #2297](https://github.com/farion1231/cc-switch/pull/2297) 中按日更新范围、同日累加的修复思路。使用原生 SwiftUI 实现，复用本项目本地日志与费用计算，沿用随包分发的 cc-switch MIT 许可声明。

小时趋势的粒度切换参考 cc-switch `32db0e5` 的 `docs/user-manual/zh/4-proxy/4.4-usage.md`；同期比较参考 cc-bar `530ef49` 的 `Main/StatsView.swift` 与 `Main/StatsOverviewModel.swift`（参考日期：2026-10-28）。本项目保留自己的自然日范围，统一按记录时间筛选，进行中的范围采用相同截止时刻，费用缺价时不计算涨跌；使用原生 Charts 和现有计费结果，沿用两项目随包分发的 MIT 声明，未复制聚合器或增加依赖。

对话用量明细的字段组织参考 cc-switch `32db0e5` 的 `src/components/usage/RequestDetailPanel.tsx`（参考日期：2026-10-28），使用原生 SwiftUI 面板与表格实现。费用缺价的显示同时核对 [issue #7321](https://github.com/farion1231/cc-switch/issues/7321)（已关闭），保留本项目的“未定价 / 部分”口径；未复制其 React 组件或增加依赖，沿用随包分发的 cc-switch MIT 声明。

本地用量统计的日志字段、缓存拆分与重复事件处理参考并改编自 cc-bar 的 `Core/Usage/CodexJSONLScanner.swift`、`ClaudeJSONLScanner.swift` 和 `UsageModels.swift`（参考日期：2026-10-28）。沿用上述 MIT 声明。实现仅保留本项目使用的日志字段与内存文件缓存，未引入其数据库、费用定价或日志监视依赖。

Git worktree 的 `.git` / `commondir` 解析改编自 cc-bar `530ef49` 的 `Core/Usage/ProjectWorktreeResolver.swift`（参考日期：2026-10-28），并核对 [Git 仓库布局](https://git-scm.com/docs/gitrepository-layout)。沿用随包分发的 cc-bar MIT 声明；本项目按每轮扫描解析目录归属，保留原始路径，不复制其分支读取、目录名回退或长期路径缓存。

统计口径与流式用量处理同时参考 [farion1231/cc-switch](https://github.com/farion1231/cc-switch) 的 `src/components/usage/UsageHero.tsx`、`src-tauri/src/services/session_usage.rs`、`session_usage_codex.rs` 和用量统计文档（参考日期：2026-10-28）。Copyright (c) 2025 Jason Young。采用 MIT License；完整原文保存在 `Resources/ThirdPartyNotices/cc-switch-LICENSE.txt`，随应用分发。未引入其 Tauri、路由代理或数据库。费用计算进一步参考并改编其 `src-tauri/src/proxy/usage/calculator.rs` 的 Decimal 分项公式和 Claude 缓存写入口径；模型价格导入参考 `src/lib/modelsDevPricing.ts` 的公开目录结构，并保留缺价状态。

内置模型价格快照与手动更新来源：[models.dev](https://models.dev/api.json)，[anomalyco/models.dev](https://github.com/anomalyco/models.dev)，取自 OpenAI / Anthropic 公开模型条目，快照日期 2026-10-28。Copyright (c) 2025 models.dev。MIT License 原文保存在 `Resources/ThirdPartyNotices/models-dev-LICENSE.txt`，随应用分发。
