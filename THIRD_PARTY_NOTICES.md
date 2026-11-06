# 第三方来源

## 跨平台应用与前端依赖

当前生产入口使用 Tauri 2 + Vue 3 + Rust + TypeScript + Vite + Apache ECharts + shadcn-vue。依赖版本由 `pnpm-lock.yaml`、`src-tauri/Cargo.lock` 固定。构建脚本从已安装包生成 `Resources/ThirdPartyNotices/dependencies-LICENSES.txt`，包含包名、版本、许可标识、来源及包中附带的许可原文；重复原文只保留一份并按编号引用。生成文件随安装包分发，不手动修改或提交。

| 组件 | 用途 | 上游许可 |
| --- | --- | --- |
| [Tauri](https://github.com/tauri-apps/tauri) 与官方插件 | 桌面窗口、托盘、通知、自启动、窗口状态、更新 | MIT OR Apache-2.0 |
| [Vue](https://github.com/vuejs/core) | 界面与响应式状态 | MIT |
| [markdown-it](https://github.com/markdown-it/markdown-it) | 更新说明 Markdown 渲染 | MIT；Copyright (c) 2014 Vitaly Puzrin, Alex Kocharin |
| [TypeScript](https://github.com/microsoft/TypeScript) | 类型检查 | Apache-2.0 |
| [Vite](https://github.com/vitejs/vite) | 前端开发与构建 | MIT |
| [Apache ECharts](https://github.com/apache/echarts) | 用量趋势、额度趋势与热力图 | Apache-2.0；包内 NOTICE 同时保留 |
| [shadcn-vue](https://github.com/unovue/shadcn-vue) | 通过官方 CLI 引入的界面组件源码 | MIT；Copyright (c) 2023 unovue |
| [Reka UI](https://github.com/unovue/reka-ui) | shadcn-vue 交互基础 | MIT |
| [Lucide](https://github.com/lucide-icons/lucide) | 线性图标 | ISC |
| [Tailwind CSS](https://github.com/tailwindlabs/tailwindcss) | 组件样式构建 | MIT |
| [rust_decimal](https://github.com/paupino/rust-decimal) | 十进制定价计算 | MIT |
| [zstd-rs](https://github.com/gyscos/zstd-rs) | Rust 压缩日志流式解码 | BSD-3-Clause |

以上许可核对于 2026-11-06，准确版本和其他传递依赖见锁文件及生成声明。shadcn-vue 生成组件的上游许可单独保存在 `Resources/ThirdPartyNotices/shadcn-vue-LICENSE.txt`；按需调整在调用层和主题 token 完成，不手改生成文件。

更新说明采用 markdown-it 15.0.3，关闭原始 HTML 与图片，链接沿用应用的外部来源入口；其 MIT 许可另存于 `Resources/ThirdPartyNotices/markdown-it-LICENSE.txt` 并随包分发。选择前比较了 marked 的额外 HTML 清理要求，并核对 markdown-it 的协议相对链接问题 [#1076](https://github.com/markdown-it/markdown-it/issues/1076)，渲染仅接受显式 HTTPS 链接。

窗口状态使用官方 `tauri-plugin-window-state`，仅恢复尺寸、位置和最大化；参考官方可见性恢复问题 [#2340](https://github.com/tauri-apps/plugins-workspace/issues/2340)，保持启动显示主窗口。许可随生成的依赖声明分发。

Rust 业务核心由本仓库 Swift 规则迁移，保留以下 cc-bar、cc-switch 等既有来源及版权声明。此前调研的 OpenTokenUsage 和 Sessions Viewer 用于比较跨平台路线，未直接复制其实现或引入依赖。

应用的缺口 Q 图标由本项目 `scripts/make-icon.swift` 绘制，1024 像素源 PNG 经官方 `pnpm tauri icon` 生成 `src-tauri/icons/` 内的平台图标。单色托盘图标以 `src-tauri/icons/tray.svg` 为源，通过 `pnpm tauri icon --png 32` 生成 `tray.png`。生成命令见 README，二进制图标不手工修改。

以下记录保留原实现的历史来源；其中 SwiftUI / AppKit / Swift Charts / Sparkle 的实现描述属于仍保留在 `Sources/` 的旧版，不表示 Tauri 应用继续链接这些框架。旧版相关许可继续保留，避免丢失历史归属。

## AIHOT 重置动态数据

Codex 重置动态通过 [AIHOT Public API](https://aihot.news/openapi-v1.json) 的 `/api/v1/codex-resets/recent` 获取公开公告、中文摘录与原帖链接，接口核对日期为 2026-10-28。客户端根据公开契约自行实现，未复制 AIHOT 或其他监测项目的代码，未引入依赖。已参考 [Issue #276](https://github.com/KKKKhazix/AIHOT/issues/276) 区分过期预告和确认事件。

AIHOT 数据服务并非 OpenAI 官方服务，数据使用遵循 [AIHOT 使用条款](https://aihot.news/terms)，不能用其框架代码的 MIT 许可代替数据授权。来源与条款链接保存在 `Resources/ThirdPartyNotices/AIHOT-NOTICE.txt`，随应用分发；动态卡片保留 AIHOT 和原帖入口。

## 界面与服务实现

本项目的菜单栏模板图像、紧凑额度面板、部分尺寸与颜色以及 Codex SVG 图标，改编自 [nanvon/cc-bar](https://github.com/nanvon/cc-bar)，参考版本 `6d990a2c3c50e8d404ea4d9982c651ce3c544baa`。

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

旧版软件更新接入参考 cc-bar `530ef49f3b5808e268181a55311e0c83cc40adff` 的 `Core/AppUpdater.swift`、`scripts/build.sh` 与发布流水线（2026-10-29）：使用 Sparkle 下载、验证、安装并重启，保留本项目双架构 DMG 与手动安装确认。嵌套签名流程按该项目改编，现归档于 `scripts/legacy/build.sh`。更新说明的原生逐行 Markdown 渲染改编自 `Main/AppUpdateWindow.swift` 的 `UpdateMarkdownView`，沿用随包分发的 cc-bar MIT 许可与版权声明。

## Sparkle 应用内更新（旧版归档）

旧 Swift 实现通过 Swift Package Manager 固定接入 [sparkle-project/Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1)，提交 `ab7d71291238df6e0492143b120c9b696a35f603`。使用官方预编译 framework、安装助手及发布签名工具，不修改上游二进制代码；当前 Tauri 产物不链接这些框架。历史流程见 [归档说明](docs/archive/updating-sparkle.md)。

Sparkle 主体采用 MIT License，并包含 BSD、zlib 等组件许可；完整上游 `LICENSE` 保存在 `Resources/ThirdPartyNotices/Sparkle-LICENSE.txt`，随应用分发。依赖版本与制品 checksum 由 `Package.swift`、`Package.resolved` 及上游 package manifest 固定。

## Zstandard 压缩日志

`Sources/CZstd/` 来自 [facebook/zstd v1.5.7](https://github.com/facebook/zstd/tree/v1.5.7)，固定提交 `f8745da6ff1ad1e7bab384bd1f9d742439278e99`。Copyright (c) Meta Platforms, Inc. and affiliates. All rights reserved. 项目提供 BSD / GPLv2 双许可证，本应用选择 BSD；完整原文保存在 `Resources/ThirdPartyNotices/zstd-LICENSE.txt`，随应用包分发。

仅静态编译官方单文件解码器 `zstddeclib.c`，保留上游生成内容和原始 `lib/zstd.h`、`lib/zstd_errors.h`，不链接 Homebrew 动态库。单文件生成默认关闭 legacy 格式和汇编，不包含压缩器或命令行工具。Swift 的按块解码循环改编自同版本 `examples/streaming_decompression.c`；同时参考 cc-bar 的块读取思路，沿用其现有 MIT 声明。

重新生成时，在该版本源码的 `build/single_file_libs/` 目录执行上游命令，将生成文件复制到 `Sources/CZstd/`，两个头文件复制到其 `include/`，并同步许可：

```sh
python3 combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.c zstddeclib-in.c
```

来源归档 `https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz` 的 SHA-256 为 `37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3`；生成的 `zstddeclib.c` 为 `5eb38abe0a7eea13674b312a006df72002d4192f0f0b4d09e6f03fb927a1f3d0`。升级时重新核对上游 release、解码相关 issue 和许可，不直接编辑生成文件。
