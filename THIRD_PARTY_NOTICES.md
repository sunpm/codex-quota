# 第三方来源

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

本次多服务接入还参考了 cc-bar 的 `Core/Credentials/ClaudeAuth.swift`、`CursorAuth.swift` 和 `Core/Quota/ClaudeQuotaClient.swift`、`CursorQuotaClient.swift` 的登录存储格式、解析及 Cursor 解密方式。`AGENTS.md` 吸收了适用于本项目的协作规则，未引入其自动发版约定。

Cursor 账号用量的接口字段、分页完整性校验和美分换算参考并改编自 cc-bar `4cc95d092e4aaf23738459abb166fb1173352691` 的 `Core/Usage/CursorUsageFetcher.swift`（2026-10-28）。同时比较 CodexBar 的 `Sources/CodexBarCore/Providers/Cursor/CursorUsageEventsFetcher.swift` 与 [历史接口 403 重试问题 #3910](https://github.com/steipete/CodexBar/issues/3910)。沿用两项目随包分发的 MIT 声明；使用本项目现有 HTTP、登录态与退避，未引入新依赖、浏览器登录、递归分窗或上游数据库。

Antigravity 本地进程发现、接口格式及响应解析参考 [steipete/CodexBar](https://github.com/steipete/CodexBar) 的 `Sources/CodexBarCore/Providers/Antigravity/AntigravityStatusProbe.swift`、`AntigravityStatusProbe+ResponseModels.swift`、`AntigravityQuotaSummaryParser.swift` 和 `AntigravityLocalhostSession.swift`。参考日期：2026-10-25。

Copyright (c) 2026 Peter Steinberger。采用 MIT License；完整声明保存在 `Resources/ThirdPartyNotices/CodexBar-LICENSE.txt`，构建时一并复制到应用包中。

本项目继续使用 Codex App Server 复用 Codex 登录，并保留自身的额度恢复通知判定。未引入外部项目的凭据刷新或应用更新服务。

主窗口、侧栏菜单及设置分组的视觉层级参考 [cc-switch v4 主界面](https://github.com/farion1231/cc-switch/blob/main/assets/release-notes/v4.0.0/main-zh.png)、[用量页面](https://github.com/farion1231/cc-switch/blob/main/assets/release-notes/v4.0.0/usage-zh.png) 与 `src/index.css` 的中性色分层（参考日期：2026-10-28）。使用本项目的 SwiftUI / AppKit 控件实现，未复制其前端组件或加入依赖；沿用下文的 cc-switch MIT 许可声明。

用量热力图参考上述用量页面的 53 周日历布局，以及 [PR #2297](https://github.com/farion1231/cc-switch/pull/2297) 中按日更新范围、同日累加的修复思路。使用原生 SwiftUI 实现，复用本项目本地日志与费用计算，沿用随包分发的 cc-switch MIT 许可声明。

小时趋势的粒度切换参考 cc-switch `32db0e5` 的 `docs/user-manual/zh/4-proxy/4.4-usage.md`；同期比较参考 cc-bar `530ef49` 的 `Main/StatsView.swift` 与 `Main/StatsOverviewModel.swift`（参考日期：2026-10-28）。本项目保留自己的自然日范围，统一按记录时间筛选，进行中的范围采用相同截止时刻，费用缺价时不计算涨跌；使用原生 Charts 和现有计费结果，沿用两项目随包分发的 MIT 声明，未复制聚合器或增加依赖。

对话用量明细的字段组织参考 cc-switch `32db0e5` 的 `src/components/usage/RequestDetailPanel.tsx`（参考日期：2026-10-28），使用原生 SwiftUI 面板与表格实现。费用缺价的显示同时核对 [issue #7321](https://github.com/farion1231/cc-switch/issues/7321)（已关闭），保留本项目的“未定价 / 部分”口径；未复制其 React 组件或增加依赖，沿用随包分发的 cc-switch MIT 声明。

本地用量统计的日志字段、缓存拆分与重复事件处理参考并改编自 cc-bar 的 `Core/Usage/CodexJSONLScanner.swift`、`ClaudeJSONLScanner.swift` 和 `UsageModels.swift`（参考日期：2026-10-28）。沿用上述 MIT 声明。实现仅保留本项目使用的日志字段与内存文件缓存，未引入其数据库、费用定价或日志监视依赖。

Codex 分段日志的线程归属核对 cc-switch 的 [分段重复会话问题 #7273](https://github.com/farion1231/cc-switch/issues/7273)、[分页线程识别问题 #7084](https://github.com/farion1231/cc-switch/issues/7084) 与 `session_usage_codex.rs` 的双 UUID 文件名解析（2026-10-28）。本项目根据文件名与首条元数据确认对应关系，仅纠正对话归属，保留已有记录去重键与计量字段；未复制上游导入器或测试代码，沿用随包分发的 cc-switch MIT 声明。

历史保留参考 cc-bar `530ef49` 的 `Core/Storage/UsageSnapshotStore.swift` 的单份快照原子提交与不覆盖无效历史的设计，并复查 [fork 重复统计问题 #7](https://github.com/nanvon/cc-bar/issues/7)（2026-10-28，已关闭）。使用 Foundation 与本项目的逐条用量记录自行实现，无新增依赖，未复制上游快照存储代码；沿用已有随包分发的 cc-bar MIT 声明。

Git worktree 的 `.git` / `commondir` 解析改编自 cc-bar `530ef49` 的 `Core/Usage/ProjectWorktreeResolver.swift`（参考日期：2026-10-28），并核对 [Git 仓库布局](https://git-scm.com/docs/gitrepository-layout)。沿用随包分发的 cc-bar MIT 声明；本项目按每轮扫描解析目录归属，保留原始路径，不复制其分支读取、目录名回退或长期路径缓存。

统计口径与流式用量处理同时参考 [farion1231/cc-switch](https://github.com/farion1231/cc-switch) 的 `src/components/usage/UsageHero.tsx`、`src-tauri/src/services/session_usage.rs`、`session_usage_codex.rs` 和用量统计文档（参考日期：2026-10-28）。Copyright (c) 2025 Jason Young。采用 MIT License；完整原文保存在 `Resources/ThirdPartyNotices/cc-switch-LICENSE.txt`，随应用分发。未引入其 Tauri、路由代理或数据库。费用计算进一步参考并改编其 `src-tauri/src/proxy/usage/calculator.rs` 的 Decimal 分项公式和 Claude 缓存写入口径；模型价格导入参考 `src/lib/modelsDevPricing.ts` 的公开目录结构，并保留缺价状态。

Antigravity 本地用量的目录布局、已完成步骤、计数与重复导出语义参考并改编自 cc-switch `6d6b7162f122ac0ce1356a14688c8c4f712db3c8` 的 `src-tauri/src/services/session_usage_agy.rs`、`src-tauri/src/session_manager/providers/agy.rs` 及 `tests/fixtures/sessions/agy.jsonl`（2026-10-28）。实施前复查双目录遮蔽问题 #8941 与旧版日志缺失计数的 PR #8914，均仍开放。沿用随包分发的 cc-switch MIT 声明；本项目直接扫描两处实际 transcript，以会话与步骤合并，不引入其索引、数据库、Protobuf、模型切换正文解析或模型价格回退。

内置模型价格快照与手动更新来源：[models.dev](https://models.dev/api.json)，[anomalyco/models.dev](https://github.com/anomalyco/models.dev)，取自 OpenAI / Anthropic 公开模型条目，快照日期 2026-10-28。Copyright (c) 2025 models.dev。MIT License 原文保存在 `Resources/ThirdPartyNotices/models-dev-LICENSE.txt`，随应用分发。

软件更新入口参考 cc-bar 的 `Core/UpdateChecker.swift` 中公开版本查询与数字版本比较的设计，并核对 GitHub Releases API 文档；本项目仅手动查询最新正式版并打开对应架构的 DMG，不引入 Sparkle 或自动安装。更新说明的原生逐行 Markdown 渲染改编自 `Main/AppUpdateWindow.swift` 的 `UpdateMarkdownView`（2026-10-29），沿用随包分发的 cc-bar MIT 许可与版权声明。

## Zstandard 压缩日志

`Sources/CZstd/` 来自 [facebook/zstd v1.5.7](https://github.com/facebook/zstd/tree/v1.5.7)，固定提交 `f8745da6ff1ad1e7bab384bd1f9d742439278e99`。Copyright (c) Meta Platforms, Inc. and affiliates. All rights reserved. 项目提供 BSD / GPLv2 双许可证，本应用选择 BSD；完整原文保存在 `Resources/ThirdPartyNotices/zstd-LICENSE.txt`，随应用包分发。

仅静态编译官方单文件解码器 `zstddeclib.c`，保留上游生成内容和原始 `lib/zstd.h`、`lib/zstd_errors.h`，不链接 Homebrew 动态库。单文件生成默认关闭 legacy 格式和汇编，不包含压缩器或命令行工具。Swift 的按块解码循环改编自同版本 `examples/streaming_decompression.c`；同时参考 cc-bar 的块读取思路，沿用其现有 MIT 声明。

重新生成时，在该版本源码的 `build/single_file_libs/` 目录执行上游命令，将生成文件复制到 `Sources/CZstd/`，两个头文件复制到其 `include/`，并同步许可：

```sh
python3 combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstddeclib.c zstddeclib-in.c
```

来源归档 `https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz` 的 SHA-256 为 `37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3`；生成的 `zstddeclib.c` 为 `5eb38abe0a7eea13674b312a006df72002d4192f0f0b4d09e6f03fb927a1f3d0`。升级时重新核对上游 release、解码相关 issue 和许可，不直接编辑生成文件。
