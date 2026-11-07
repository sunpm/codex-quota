# 第三方来源

## 跨平台应用与前端依赖

当前生产入口使用 Tauri 2 + Vue 3 + Rust + TypeScript + Vite + Apache ECharts + shadcn-vue。依赖版本由 `pnpm-lock.yaml`、`src-tauri/Cargo.lock` 固定。构建脚本从已安装包生成 `Resources/ThirdPartyNotices/dependencies-LICENSES.txt`，包含包名、版本、许可标识、来源及包中附带的许可原文；重复原文只保留一份并按编号引用。生成文件随安装包分发，不手动修改或提交。

| 组件 | 用途 | 上游许可 |
| --- | --- | --- |
| [Tauri](https://github.com/tauri-apps/tauri) 与官方插件 | 桌面窗口、托盘、通知、自启动、窗口状态、更新 | MIT OR Apache-2.0 |
| [Vue](https://github.com/vuejs/core) | 界面与响应式状态 | MIT |
| [@pmun/utils](https://github.com/sunpm/sunpm-utils) | 类型判断、本地日期运算、分组排序、金额尾零与草稿拷贝 | MIT |
| [Day.js](https://github.com/iamkun/dayjs) | @pmun/utils 的日期处理依赖 | MIT |
| [markdown-it](https://github.com/markdown-it/markdown-it) | 更新说明 Markdown 渲染 | MIT；Copyright (c) 2014 Vitaly Puzrin, Alex Kocharin |
| [DOMPurify](https://github.com/cure53/DOMPurify) | 更新说明 HTML 清理 | Apache-2.0 OR MPL-2.0；本应用选择 Apache-2.0 |
| [TypeScript](https://github.com/microsoft/TypeScript) | 类型检查 | Apache-2.0 |
| [Vite](https://github.com/vitejs/vite) | 前端开发与构建 | MIT |
| [Apache ECharts](https://github.com/apache/echarts) | 用量趋势、额度趋势与热力图 | Apache-2.0；包内 NOTICE 同时保留 |
| [shadcn-vue](https://github.com/unovue/shadcn-vue) | 通过官方 CLI 引入的界面组件源码 | MIT；Copyright (c) 2023 unovue |
| [Reka UI](https://github.com/unovue/reka-ui) | shadcn-vue 交互基础 | MIT |
| [Lucide](https://github.com/lucide-icons/lucide) | 线性图标 | ISC |
| [Tailwind CSS](https://github.com/tailwindlabs/tailwindcss) | 组件样式构建 | MIT |
| [rust_decimal](https://github.com/paupino/rust-decimal) | 十进制定价计算 | MIT |
| [zstd-rs](https://github.com/gyscos/zstd-rs) | Rust 压缩日志流式解码 | BSD-3-Clause |

以上许可核对于 2026-11-06，准确版本和其他传递依赖见锁文件及生成声明。shadcn-vue 生成组件（含 NativeSelect）的上游许可单独保存在 `Resources/ThirdPartyNotices/shadcn-vue-LICENSE.txt`；组件通过官方 CLI 引入，按需调整在调用层和主题 token 完成，不手改生成文件。

`@pmun/utils` 0.17.0 与 Day.js 的 MIT 许可于 2026-11-07 核对，随生成的依赖声明分发；工具方法的使用边界见 [开发说明](docs/development.md#通用工具方法)。

更新说明采用 markdown-it 15.0.3 解析 Markdown 与 GitHub 注释、折叠说明，再由 DOMPurify 3.4.17 对完整渲染结果按标签、属性白名单清理；不加载图片，链接仅接受显式 HTTPS 并沿用应用的外部来源入口。两者许可分别保存在 `Resources/ThirdPartyNotices/markdown-it-LICENSE.txt` 与 `Resources/ThirdPartyNotices/DOMPurify-LICENSE.txt`，并随包分发。选择前比较了 marked、sanitize-html 与 DOMPurify；后者直接使用 WebView 的 DOM，无需额外 HTML 解析器。已核对 markdown-it 的协议相对链接问题 [#1076](https://github.com/markdown-it/markdown-it/issues/1076)、禁用 HTML 时的注释解析问题 [#1060](https://github.com/markdown-it/markdown-it/issues/1060)，以及 DOMPurify 对不完整 HTML 自动补齐的行为 [#838](https://github.com/cure53/DOMPurify/issues/838)，因此清理完整文档而非单独处理 HTML token。

窗口状态使用官方 `tauri-plugin-window-state`，仅恢复尺寸、位置和最大化；参考官方可见性恢复问题 [#2340](https://github.com/tauri-apps/plugins-workspace/issues/2340)，保持启动显示主窗口。许可随生成的依赖声明分发。

Rust 业务核心由本仓库 Swift 规则迁移，保留以下 cc-bar、cc-switch 等既有来源及版权声明。此前调研的 OpenTokenUsage 和 Sessions Viewer 用于比较跨平台路线，未直接复制其实现或引入依赖。

应用的缺口 Q 图标由本项目 `scripts/make-icon.swift` 绘制，1024 像素源 PNG 经官方 `pnpm tauri icon` 生成 `src-tauri/icons/` 内的平台图标。单色托盘图标以 `src-tauri/icons/tray.svg` 为源，通过 `pnpm tauri icon --png 32` 生成 `tray.png`。生成命令见 README，二进制图标不手工修改。

以下记录保留原实现的历史来源；其中 SwiftUI / Swift Charts / Sparkle 的实现描述属于已移除的旧版。当前 Rust 沿用的设计与逻辑继续保留对应来源和许可；仅供旧应用使用的依赖许可随旧源码保存在 Git 历史中。当前 macOS 集成仍通过 Rust 调用 AppKit 等系统框架。

## AIHOT 重置动态数据

Codex 重置动态通过 [AIHOT Public API](https://aihot.news/openapi-v1.json) 的 `/api/v1/codex-resets/recent` 获取公开公告、中文摘录与原帖链接，接口核对日期为 2026-10-28。客户端根据公开契约自行实现，未复制 AIHOT 或其他监测项目的代码，未引入依赖。已参考 [Issue #276](https://github.com/KKKKhazix/AIHOT/issues/276) 区分过期预告和确认事件。

AIHOT 数据服务并非 OpenAI 官方服务，数据使用遵循 [AIHOT 使用条款](https://aihot.news/terms)，不能用其框架代码的 MIT 许可代替数据授权。来源与条款链接保存在 `Resources/ThirdPartyNotices/AIHOT-NOTICE.txt`，随应用分发；动态卡片保留 AIHOT 和原帖入口。

## 界面与服务实现

旧版菜单栏模板图像、紧凑额度面板、部分尺寸与颜色以及 Codex SVG 图标，改编自 [nanvon/cc-bar](https://github.com/nanvon/cc-bar)，参考版本 `6d990a2c3c50e8d404ea4d9982c651ce3c544baa`。

参考文件：

- `MenuBar/MenuBarLabel.swift`
- `MenuBar/PopoverRootView.swift`
- `Main/DesignSystem.swift`
- `Resources/Logos/codex.svg`

Copyright (c) 2026 nanvon。采用 MIT License；完整声明保存在 `Resources/ThirdPartyNotices/cc-bar-LICENSE.txt`，构建时一并复制到应用包中。

`AGENTS.md` 吸收了 cc-bar 中适用于本项目的协作规则，未引入其自动发版约定。

旧版 Claude Code、Cursor 和 Antigravity 接入曾参考 cc-bar 与 [steipete/CodexBar](https://github.com/steipete/CodexBar) 的凭据、额度和用量实现；这些接入现已移除。为保留历史来源，继续附带 CodexBar 的 MIT 声明（Copyright (c) 2026 Peter Steinberger），完整原文位于 `Resources/ThirdPartyNotices/CodexBar-LICENSE.txt`。

额度趋势的悬停交互核对了 CodexBar 的悬停选错日期问题 [#3062](https://github.com/steipete/CodexBar/issues/3062)（2026-10-30）。使用本项目原生 Charts 与实测点吸附逻辑实现，空白时段明确显示“无采样”，未复制上游组件或增加依赖；沿用随包分发的 CodexBar MIT 声明。

本项目继续使用 Codex App Server 复用 Codex 登录，并保留自身的额度恢复通知判定。未引入外部项目的凭据刷新服务。当前应用内更新使用 Tauri updater；下文 Sparkle 声明仅对应归档的 Swift 实现。

主窗口、侧栏菜单及设置分组的视觉层级参考 [cc-switch v4 主界面](https://github.com/farion1231/cc-switch/blob/main/assets/release-notes/v4.0.0/main-zh.png)、[用量页面](https://github.com/farion1231/cc-switch/blob/main/assets/release-notes/v4.0.0/usage-zh.png) 与 `src/index.css` 的中性色分层（参考日期：2026-10-28）。使用本项目的 SwiftUI / AppKit 控件实现，未复制其前端组件或加入依赖；沿用下文的 cc-switch MIT 许可声明。

侧栏今日指标的紧凑数值与完整悬停、辅助标签参考 cc-switch `f283a55f6fbcadb7f1c954c76a34f307ea3856c8` 的 `src/components/shell/Sidebar.tsx`（2026-11-05）。本项目使用原生 SwiftUI 将指标独立放在侧栏底部，支持四项多选并逐行显示，保留已有统计实现与真实零值、未读取、缺价状态；未复制 React 组件或引入依赖，沿用随包分发的 cc-switch MIT 声明。

用量热力图参考上述用量页面的 53 周日历布局，以及 [PR #2297](https://github.com/farion1231/cc-switch/pull/2297) 中按日更新范围、同日累加的修复思路。使用原生 SwiftUI 实现，复用本项目本地日志与费用计算，沿用随包分发的 cc-switch MIT 许可声明。

小时趋势的粒度切换参考 cc-switch `32db0e5` 的 `docs/user-manual/zh/4-proxy/4.4-usage.md`；同期比较参考 cc-bar `530ef49` 的 `Main/StatsView.swift` 与 `Main/StatsOverviewModel.swift`（参考日期：2026-10-28）。本项目保留自己的自然日范围，统一按记录时间筛选，进行中的范围采用相同截止时刻，费用缺价时不计算涨跌；使用原生 Charts 和现有计费结果，沿用两项目随包分发的 MIT 声明，未复制聚合器或增加依赖。

对话用量明细的字段组织参考 cc-switch `32db0e5` 的 `src/components/usage/RequestDetailPanel.tsx`（参考日期：2026-10-28），使用原生 SwiftUI 面板与表格实现。费用缺价的显示同时核对 [issue #7321](https://github.com/farion1231/cc-switch/issues/7321)（已关闭），保留本项目的“未定价 / 部分”口径；未复制其 React 组件或增加依赖，沿用随包分发的 cc-switch MIT 声明。

用量明细的紧凑数字、时间、模型排版和今日指标配置参考 cc-switch `9941a6455ef9405cf9d3620057fddd283223a607` 的 `src/components/usage/format.ts`、`RequestLogTable.tsx`、`usageTable.ts` 与 `UsageDisplaySection.tsx`；请求计时边界改编自 `src-tauri/src/services/session_usage_codex.rs` 的 `RequestTimer`，并核对 [issue #7832](https://github.com/farion1231/cc-switch/issues/7832) 与 [PR #7635](https://github.com/farion1231/cc-switch/pull/7635)（2026-10-30）。保留本项目 SwiftUI、日志去重与计费实现；会话速度和首字仅显示带近似标识的估算，缓存写入保留缺失与零值区别。沿用 cc-switch 的 MIT 声明及随包许可，未引入其代理、数据库或前端依赖。

本地 Codex 用量统计的日志字段、缓存拆分与重复事件处理参考并改编自 cc-bar 的 `Core/Usage/CodexJSONLScanner.swift` 和 `UsageModels.swift`（参考日期：2026-10-28）。沿用上述 MIT 声明。实现仅保留本项目使用的日志字段与内存文件缓存，未引入其数据库、费用定价或日志监视依赖。旧版参考 `ClaudeJSONLScanner.swift` 的 Claude 解析已移除。

普通日志增量读取参考 cc-bar 的 [JSONLLineReader.swift](https://github.com/nanvon/cc-bar/blob/main/Core/Usage/JSONLLineReader.swift) 与 [CodexJSONLScanner.swift](https://github.com/nanvon/cc-bar/blob/main/Core/Usage/CodexJSONLScanner.swift) 的完整行偏移、解析上下文和截断重置设计，同时比较 CodexBar 的 [CostUsageJsonl.swift](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Vendored/CostUsage/CostUsageJsonl.swift) 对未完成末行的处理，并核对其大量日志读取问题 [#4620](https://github.com/steipete/CodexBar/issues/4620) 与内存问题 [#3323](https://github.com/steipete/CodexBar/issues/3323)（2026-11-05）。两项目均为仍在维护的 MIT 项目；本项目基于现有 Foundation 解析器实现，仅保存内存续读状态，保留自身去重及计时口径，不引入数据库、文件监视或新的依赖。来源说明与已有两项目许可随包分发，见 `Resources/ThirdPartyNotices/usage-scanning-NOTICE.txt`。

Codex 分段日志的线程归属核对 cc-switch 的 [分段重复会话问题 #7273](https://github.com/farion1231/cc-switch/issues/7273)、[分页线程识别问题 #7084](https://github.com/farion1231/cc-switch/issues/7084) 与 `session_usage_codex.rs` 的双 UUID 文件名解析（2026-10-28）。本项目根据文件名与首条元数据确认对应关系，仅纠正对话归属，保留已有记录去重键与计量字段；未复制上游导入器或测试代码，沿用随包分发的 cc-switch MIT 声明。

历史保留参考 cc-bar `530ef49` 的 `Core/Storage/UsageSnapshotStore.swift` 的单份快照原子提交与不覆盖无效历史的设计，并复查 [fork 重复统计问题 #7](https://github.com/nanvon/cc-bar/issues/7)（2026-10-28，已关闭）。使用 Foundation 与本项目的逐条用量记录自行实现，无新增依赖，未复制上游快照存储代码；沿用已有随包分发的 cc-bar MIT 声明。

Git worktree 的 `.git` / `commondir` 解析改编自 cc-bar `530ef49` 的 `Core/Usage/ProjectWorktreeResolver.swift`（参考日期：2026-10-28），并核对 [Git 仓库布局](https://git-scm.com/docs/gitrepository-layout)。沿用随包分发的 cc-bar MIT 声明；本项目按每轮扫描解析目录归属，保留原始路径，不复制其分支读取、目录名回退或长期路径缓存。

统计口径与用量处理同时参考 [farion1231/cc-switch](https://github.com/farion1231/cc-switch) 的 `src/components/usage/UsageHero.tsx`、`src-tauri/src/services/session_usage.rs`、`session_usage_codex.rs` 和用量统计文档（参考日期：2026-10-28）。Copyright (c) 2025 Jason Young。采用 MIT License；完整原文保存在 `Resources/ThirdPartyNotices/cc-switch-LICENSE.txt`，随应用分发。未引入其 Tauri、路由代理或数据库。费用计算进一步参考并改编其 `src-tauri/src/proxy/usage/calculator.rs` 的 Decimal 分项公式；模型价格导入参考 `src/lib/modelsDevPricing.ts` 的公开目录结构，并保留缺价状态。旧版 Claude 缓存计费规则已移除。

旧版 Antigravity 本地用量曾参考并改编 cc-switch `6d6b7162f122ac0ce1356a14688c8c4f712db3c8` 的 `src-tauri/src/services/session_usage_agy.rs`、`src-tauri/src/session_manager/providers/agy.rs` 及 `tests/fixtures/sessions/agy.jsonl`（2026-10-28）；相关采集与解析现已移除。

内置模型价格快照与手动更新来源：[models.dev](https://models.dev/api.json)，[anomalyco/models.dev](https://github.com/anomalyco/models.dev)，取自 OpenAI 公开模型条目，快照日期 2026-10-28。Copyright (c) 2025 models.dev。MIT License 原文保存在 `Resources/ThirdPartyNotices/models-dev-LICENSE.txt`，随应用分发。

旧版软件更新接入参考 cc-bar `530ef49f3b5808e268181a55311e0c83cc40adff` 的 `Core/AppUpdater.swift`、`scripts/build.sh` 与发布流水线（2026-10-29）：使用 Sparkle 下载、验证、安装并重启，保留本项目双架构 DMG 与手动安装确认。嵌套签名流程按该项目改编，相关脚本现仅保存在 Git 历史中。更新说明的原生逐行 Markdown 渲染改编自 `Main/AppUpdateWindow.swift` 的 `UpdateMarkdownView`，沿用随包分发的 cc-bar MIT 许可与版权声明。

## 已移除的旧版依赖

旧 Swift 应用曾使用 [Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1) 和 [Zstandard v1.5.7](https://github.com/facebook/zstd/tree/v1.5.7) 单文件解码器。Sparkle 主体采用 MIT，并包含 BSD、zlib 等组件；Zstandard 当时选择 BSD 许可。两者的旧源码、锁定版本及完整许可保存在 [迁移前版本](https://github.com/sunpm/codex-quota/tree/752a5f9b430a39a1b42d873c08151eb845acf690)，历史升级验收见 [归档说明](docs/archive/updating-sparkle.md)。

当前应用使用 Tauri updater 与 Rust `zstd` 依赖，不再分发 Sparkle 或旧 CZstd 源码；当前压缩依赖及其底层库的版本、来源和完整许可由 `scripts/collect-licenses.mjs` 从锁定的 Cargo 依赖生成并随包分发。
