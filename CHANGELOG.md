# 版本历史

以下按仓库 Git 标签和提交记录整理。各版本安装包与发布说明见 [GitHub Releases](https://github.com/sunpm/codex-quota/releases)。旧版本提及的其他服务属于历史功能，当前应用仅接入和展示 Codex。

## [0.25.9](https://github.com/sunpm/codex-quota/releases/tag/v0.25.9)

<!-- Release notes generated using configuration in .github/release.yml at 2d6cbb8c070fb67f2b58d6eb6ab37b3420a20bac -->

### What's Changed
#### 更新内容
* fix(updates): 修复自动更新提示并展示更新说明 by @sunpm in https://github.com/sunpm/codex-quota/pull/49
* refactor(release): 接入共享 Tauri 发布流程 by @sunpm in https://github.com/sunpm/codex-quota/pull/50
* fix(quota): 修复反重力单额度分组排列 by @sunpm in https://github.com/sunpm/codex-quota/pull/51
* feat: 支持精确时间筛选、图表明细跳转与低额度提醒 by @sunpm in https://github.com/sunpm/codex-quota/pull/52


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.8...v0.25.9

## [0.25.8](https://github.com/sunpm/codex-quota/releases/tag/v0.25.8)

<!-- Release notes generated using configuration in .github/release.yml at 5f8a5db65c1f04cbe3bfd7a2e0b317b15fc4474b -->

### What's Changed
#### 更新内容
* feat: 优化额度筛选、托盘展示与公开重置动态 by @sunpm in https://github.com/sunpm/codex-quota/pull/48


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.7...v0.25.8

## [0.25.7](https://github.com/sunpm/codex-quota/releases/tag/v0.25.7)

<!-- Release notes generated using configuration in .github/release.yml at 7f906ccdb593c2cebb826fced65f925c5d96fe88 -->

### What's Changed
#### 更新内容
* feat(tray): 拆分 Codex 与 Antigravity 独立状态项 by @sunpm in https://github.com/sunpm/codex-quota/pull/47


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.6...v0.25.7

## [0.25.6](https://github.com/sunpm/codex-quota/releases/tag/v0.25.6)

<!-- Release notes generated using configuration in .github/release.yml at 13ee828bc4cac1328a3644cb67377c046fdc953d -->

### What's Changed
#### 更新内容
* feat(usage): 接入 Antigravity 本地用量分析 by @sunpm in https://github.com/sunpm/codex-quota/pull/46


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.5...v0.25.6

## [0.25.5](https://github.com/sunpm/codex-quota/releases/tag/v0.25.5)

<!-- Release notes generated using configuration in .github/release.yml at 575f53912a4f3d31db6ee272482724ccee3c0a2b -->

### What's Changed
#### 更新内容
* feat(antigravity): 增加额度监测与公开重置动态 by @sunpm in https://github.com/sunpm/codex-quota/pull/44
* fix(antigravity): 隐藏未就绪的额度卡片 by @sunpm in https://github.com/sunpm/codex-quota/pull/45


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.4...v0.25.5

## [0.25.4](https://github.com/sunpm/codex-quota/releases/tag/v0.25.4)

<!-- Release notes generated using configuration in .github/release.yml at 34975b8c875c5c415472afa3dd3ad25996ebab9f -->

### What's Changed
#### 更新内容
* fix(ui): 修复菜单栏图标裁切并精简用量涨跌展示 by @sunpm in https://github.com/sunpm/codex-quota/pull/42
* chore(deps): 放宽 pnpm 与依赖版本范围并同步 CI by @sunpm in https://github.com/sunpm/codex-quota/pull/43


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.3...v0.25.4

## [0.25.3](https://github.com/sunpm/codex-quota/releases/tag/v0.25.3)

<!-- Release notes generated using configuration in .github/release.yml at 8f63c9f87ccce4db1a53dda1f23c77999be7d96a -->

### What's Changed
#### 更新内容
* fix(ui): 完善用量筛选与未定价展示 by @sunpm in https://github.com/sunpm/codex-quota/pull/40
* feat(release): 接入手动发布并统一版本与变更日志 by @sunpm in https://github.com/sunpm/codex-quota/pull/41


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.1...v0.25.3

## [0.25.2](https://github.com/sunpm/codex-quota/releases/tag/v0.25.2)

<!-- Release notes generated using configuration in .github/release.yml at v0.25.2 -->

### What's Changed
#### 更新内容
* fix(ui): 完善用量筛选与未定价展示 by @sunpm in https://github.com/sunpm/codex-quota/pull/40


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.1...v0.25.2

## [0.25.1](https://github.com/sunpm/codex-quota/releases/tag/v0.25.1)

<!-- Release notes generated using configuration in .github/release.yml at v0.25.1 -->

### What's Changed
#### 更新内容
* fix(desktop): 完善用量展示并清理旧 Swift 实现 by @sunpm in https://github.com/sunpm/codex-quota/pull/39


**Full Changelog**: https://github.com/sunpm/codex-quota/compare/v0.25.0...v0.25.1

## [0.25.0](https://github.com/sunpm/codex-quota/releases/tag/v0.25.0)

- 合并对话和项目为“明细”页，共用筛选条件，并在重新打开应用后恢复视图与筛选状态。
- 显示完整 Tokens 数字，统一选择控件与焦点样式，修正键盘调宽和页面滚动复位。
- 根据剩余时间显示额度倒计时状态，并为最早到期的有效重置卡增加倒计时。
- 保留额度趋势的独立采样点，空白时段显示“无采样”；补齐同期增减量与图表双指标提示。
- 完善系统通知样式识别和持续提醒引导。
- 正确渲染更新说明中的注释与折叠内容；统计范围说明支持点击与键盘操作。
- 精简新用户入门说明，分离使用、开发与版本历史文档，补充随外观切换的浅深色界面截图。

## [0.24.0](https://github.com/sunpm/codex-quota/releases/tag/v0.24.0)

- 为重置卡到期和额度重置分别配置多个提前提醒时间，并跨重启去重。
- 合并错过的提醒时间点，关闭提醒期间继续更新观测状态。
- 默认额度刷新间隔调整为 1 分钟，完善提醒设置的键盘与焦点操作。

## [0.23.1](https://github.com/sunpm/codex-quota/releases/tag/v0.23.1)

- 修正缺价费用占比和旧历史计费档位标记，自动补全日志模型的定价入口。
- 恢复高消耗对话、完整分组汇总与详情上下文，支持精确费用提示和列宽调整。
- 补齐菜单栏、窗口恢复、macOS 菜单与图标，以及重置动态和到期状态展示。
- 统一 Markdown 更新说明与首次展示流程，向各平台安装包嵌入同一份版本说明。

## [0.23.0](https://github.com/sunpm/codex-quota/releases/tag/v0.23.0)

- 从 Swift 迁移至 Tauri、Vue 和 Rust，支持 macOS Apple Silicon、Intel 与 Windows x64。
- 保留 Codex 监测、用量分析和历史兼容，统一主窗口、托盘、设置与更新交互。
- 改用 Tauri 签名更新包，统一三平台构建、更新清单和校验值。
- 修复更新清单缺失时的版本检查、macOS 通知发送和图表空白，优化侧栏与多选设置。

从旧 Swift / Sparkle 版本升级时，需退出旧应用并手动安装一次跨平台版本。macOS 保留原 Bundle ID、数据目录和偏好，后续使用 Tauri 应用内更新；详见 [迁移说明](docs/updating.md#从-swift--sparkle-版本迁移)。

## [0.23.0-beta.1](https://github.com/sunpm/codex-quota/releases/tag/v0.23.0-beta.1)

- 提供 Tauri 跨平台桌面预发布版本，统一布局、构建和发布说明。
- 修复手动打包和 Windows 编译，配置独立的更新签名。

## [0.21.2](https://github.com/sunpm/codex-quota/releases/tag/v0.21.2)

- 使用嵌入式侧栏，保留分隔线和调宽布局。
- 手动检查更新后以原生弹窗反馈结果，后台检查保持静默。

## [0.21.1](https://github.com/sunpm/codex-quota/releases/tag/v0.21.1)

- 复用未变化的费用和按日汇总，减少重复统计。
- 增量读取追加日志，文件截断或替换后重新解析，保留去重和请求计时口径。

## [0.21.0](https://github.com/sunpm/codex-quota/releases/tag/v0.21.0)

- 支持拖动侧栏与内容区之间的分隔线调整宽度。

## [0.20.0](https://github.com/sunpm/codex-quota/releases/tag/v0.20.0)

- 将今日用量移至侧栏底部，支持多选指标或全部隐藏。

## [0.19.0](https://github.com/sunpm/codex-quota/releases/tag/v0.19.0)

- 增加侧栏今日指标、可配置明细列及日志耗时与首字时间估算。
- 优化表格、费用提示和图表时间轴与悬停交互。

## [0.18.0](https://github.com/sunpm/codex-quota/releases/tag/v0.18.0)

- 在软件更新区域展示新版 Markdown 说明，并嵌入双架构更新清单。
- 支持刷新间隔预设和自定义浮层。

## [0.17.1](https://github.com/sunpm/codex-quota/releases/tag/v0.17.1)

- 优化设置分组和按钮对齐，将模型定价移入独立管理面板。
- 统一侧栏图标，移除窗口重新获得焦点时的重复日志扫描。

## [0.17.0](https://github.com/sunpm/codex-quota/releases/tag/v0.17.0)

- 展示重置卡数量与到期明细，支持提前 24 小时提醒和跨重启去重。
- 统一按钮与设置分组，固定更新检查区域布局。

## [0.16.0](https://github.com/sunpm/codex-quota/releases/tag/v0.16.0)

- 接入 Sparkle 应用内更新，经用户确认后下载、验签、安装并重启。
- 生成双架构签名更新清单，完整上传附件后再公开发布。
- 精简额度页，重组监测设置并增加动画开关。

## [0.15.2](https://github.com/sunpm/codex-quota/releases/tag/v0.15.2)

- 将应用统一更名为 Codex Quota，保留原应用标识、配置键与历史目录。
- 固定安装包文件名，更新仓库与下载链接并兼容旧附件命名。

## [0.15.1](https://github.com/sunpm/codex-quota/releases/tag/v0.15.1)

- 统一菜单栏图标与原生菜单入口，提供打开面板和退出操作。
- 精简用量与设置中的重复提示，更新界面截图。

## [0.15.0](https://github.com/sunpm/codex-quota/releases/tag/v0.15.0)

- 增加最近 24 小时和 7 天额度趋势，重置或采样中断时断开曲线。
- 支持配置并保存额度刷新间隔，缩短导航选中动画。

## [0.14.0](https://github.com/sunpm/codex-quota/releases/tag/v0.14.0)

- 优化用量筛选、日期浮层、表格布局和选中动画。
- 减少分组与排行的重复计算，避免路径名称解析访问文件系统。

## [0.13.1](https://github.com/sunpm/codex-quota/releases/tag/v0.13.1)

- 避免离线窗口检查显示 Dock 图标或抢占焦点。

## [0.13.0](https://github.com/sunpm/codex-quota/releases/tag/v0.13.0)

- 聚焦 Codex，移除其他服务接入与界面，保留旧历史和自定义价格兼容。
- 优化用量层级、表格和对话识别，采用原生控件并保留旧系统回退。
- 随安装包保存更新说明，在每个版本首次打开时展示。

## [0.12.0](https://github.com/sunpm/codex-quota/releases/tag/v0.12.0)

- 默认启动时及约每 24 小时自动检查正式版更新，支持关闭自动检查。
- 关闭主窗口后继续后台运行，从菜单栏重新打开同一窗口。
- 从最近成功发布的正式版累计生成更新说明。

## [0.11.0](https://github.com/sunpm/codex-quota/releases/tag/v0.11.0)

- 增加正式版更新检查、版本说明和按 Mac 架构匹配的下载入口。
- 补充首次打开被 macOS 阻止时的操作指引。

## [0.10.1](https://github.com/sunpm/codex-quota/releases/tag/v0.10.1)

- 优化额度与时间信息层级，统一用量筛选和原生汇总表格。

## [0.10.0](https://github.com/sunpm/codex-quota/releases/tag/v0.10.0)

- 接入 AIHOT 公开重置动态及独立通知，保留个人额度恢复逻辑。
- 修复原地构建后 Finder 图标未刷新的问题。

## [0.9.0](https://github.com/sunpm/codex-quota/releases/tag/v0.9.0)

- 支持压缩日志和已采集用量历史持久化。
- 将 Codex 分段用量归入原对话，并修正已有历史的会话归属。
- 增加 Cursor 账号用量历史与 Antigravity 本地用量统计。

## [0.8.2](https://github.com/sunpm/codex-quota/releases/tag/v0.8.2)

- 将应用和通知的系统显示名称统一为 Codex Quota Dock。

## [0.8.1](https://github.com/sunpm/codex-quota/releases/tag/v0.8.1)

- 增加对话用量明细、速度档位拆分、小时趋势和同期比较。
- 按主仓库归并 worktree 用量，保留原始工作目录。
- 增加持续通知引导和浅深色图标。

## [0.8.0](https://github.com/sunpm/codex-quota/releases/tag/v0.8.0) / [0.7.1](https://github.com/sunpm/codex-quota/releases/tag/v0.7.1)

- 两个标签对应同一源码提交，分别提供 Apple Silicon 与 Intel DMG 安装包及校验值。

## [0.7.0](https://github.com/sunpm/codex-quota/releases/tag/v0.7.0)

- 提供 Codex 额度监测、重置倒计时、恢复通知和菜单栏控制面板。
- 支持当时的多服务额度监测，以及 Codex 与 Claude Code 本地用量统计。
- 增加模型定价、费用估算、日期筛选和 53 周热力图。
- 配置标签发布、通用 Mac 应用构建与自动生成发布说明。
