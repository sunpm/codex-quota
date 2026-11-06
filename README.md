# Codex Quota

在一个桌面窗口中查看 Codex 的剩余额度、Token 用量和 API 等价费用，额度恢复时收到通知，也可在菜单栏或系统托盘快速查看。

[下载发行版](https://github.com/sunpm/codex-quota/releases/latest) · [更新记录](https://github.com/sunpm/codex-quota/releases) · [反馈问题](https://github.com/sunpm/codex-quota/issues)

当前源码使用 **Tauri 2、Vue 3、Rust、TypeScript、Vite、Apache ECharts 和 shadcn-vue**，目标平台为 macOS 13+（Apple Silicon / Intel）与 Windows 10 / 11 x64。已发布版本的功能和平台以对应 Release 附件为准。

## 安装与接入

| 平台 | 安装包 |
| --- | --- |
| macOS Apple Silicon | `CodexQuota-macOS-AppleSilicon.dmg` |
| macOS Intel | `CodexQuota-macOS-Intel.dmg` |
| Windows x64 | `CodexQuota-Windows-x64-setup.exe` |

macOS 打开 DMG 后将应用拖入“应用程序”。Windows 运行安装器，按当前用户安装；界面需要 Microsoft Edge WebView2 Runtime，缺少时安装器会引导安装。

先安装并登录 Codex，再打开 Codex Quota。额度查询复用 `codex app-server`，本应用不保存或改写 Codex 凭据。Windows 使用原生 Windows Codex；当前不自动连接 WSL 中的 Codex。可通过 `CODEX_QUOTA_CLI` 指定 CLI 可执行文件，通过 `CODEX_HOME` 指定日志目录。

从旧 Swift / Sparkle 版本升级时，先退出旧应用，**手动安装一次跨平台版本**。macOS 保留 Bundle ID `local.codexquotadock.app` 和 `CodexQuotaDock` 数据目录，首次启动导入旧偏好。后续更新使用 Tauri 签名更新包；旧 Sparkle appcast 不用于安装新更新包，详见 [更新说明](docs/updating.md)。

当前发布配置未接入 Apple Developer ID 公证或 Windows 代码签名证书。macOS 首次运行被阻止时，确认下载来源后，在“系统设置 → 隐私与安全性”选择该应用的“仍要打开”。更新包签名用于验证更新来源，不代表通过了平台公证。

## 日常使用

侧栏包含用量、对话、项目、额度和设置，切换菜单时页面与明细表滚动位置回到起点。界面跟随系统浅色 / 深色外观，数值使用等宽数字；用量、对话和项目页顶部的总 Tokens 及模型、对话、项目汇总表的 Tokens 均显示带千位分隔符的完整数字，逐条明细的 Token 拆分保留简写、悬停查看完整值；“动画特性”与系统减少动态效果共同控制动效。选择框采用统一的细边框与箭头外观，保留系统选项菜单和键盘操作。

- **额度**：显示接口实际返回的额度窗口、剩余百分比、本地倒计时和重置卡。进入额度页后台刷新；默认每 1 分钟查询，可设置不少于 30 秒的间隔。缺失额度显示不可用，失败保留上次读数并标明过期。启动、唤醒和重新开启监测会刷新，所有入口遵守服务端冷却时间。
- **用量**：查看 Tokens、API 等价费用、缓存命中率、用量趋势、高消耗对话前五项、完整模型 / 项目汇总和最近 53 周热力图；可按日期与模型筛选。今天和昨天使用小时趋势，较长范围使用每日趋势。同期对比显示百分比与绝对增减量，悬停查看上期值；采用等长自然日范围，进行中的范围对齐当地截止时刻，费用缺价时不计算涨跌。趋势图与热力图悬停同时显示 Tokens、费用及未定价记录数。
- **对话与项目**：按实际用量汇总，查看逐条时间、模型、Token 拆分、费用、计费档位及可确认的速度与首字估算。可确认的 Git worktree 归入主仓库，子模块独立；无法确认时保留原始目录。详情可选择复制完整会话 ID 与工作目录，展示主仓库映射、当前范围总量和多档位汇总；悬停费用查看精确值，拖动表头分隔线或聚焦后按左右方向键调整列宽。
- **设置**：管理监测、恢复通知、额度重置前提醒、重置卡到期提醒、公开动态通知、菜单栏 / 托盘、登录启动、刷新间隔、今日指标、明细列、模型价格、历史和更新。“用量显示”直接列出已选指标与明细列，修改后立即更新。监测与托盘开关独立，用量分析不依赖监测开关。

对话与项目页分别记住日期范围、模型、Tokens / 费用指标和搜索条件，切换页面或重新打开应用后恢复；“今天”“7 天”等范围随当前日期滚动，自定义范围保留所选日期。筛选偏好仅保存在本机，所选模型暂无记录时保留选择并显示空结果。

启动恢复上次的窗口位置、尺寸与最大化状态，并显示主窗口。macOS Dock 图标跟随系统外观，`⌘0` 打开面板，系统菜单保留隐藏、缩放与前置全部窗口。

菜单栏优先显示 Codex 额度桶，按窗口时长取前两个；没有 Codex 桶时回退到其他窗口。悬停可查看窗口名称、剩余额度、当地重置时间与具体错误。

关闭窗口后继续监测，从菜单栏 / 托盘或应用入口重新打开同一窗口；退出应用才停止后台任务并清理本应用启动的子进程。macOS 有可用菜单栏入口时隐藏 Dock 图标，否则保留 Dock 入口。Windows 关闭后可从托盘或再次启动应用恢复窗口。

本机日志只在窗口可见时定期扫描，默认每 30 秒一次，也可手动刷新。读取本地日志不发起模型请求。额度与公开重置动态各自独立调度，倒计时在本地计算。

额度趋势保留每个实测点，重置或观测中断处不连线，独立采样点也可见。悬停只读取附近的真实采样；空白时段显示“无采样”，不借用远处读数。

额度倒计时与最早到期的有效重置卡倒计时共用时间分级：超过 24 小时为绿色，超过 6 小时至 24 小时为黄色，超过 1 小时至 6 小时为橙色，1 小时以内为红色。重置卡倒计时显示在到期日期旁，卡片到期后移至下一张即将到期的卡；未知时间保持中性色。颜色随本地倒计时更新。

### 提醒与公开动态

macOS 通知使用系统通知中心，应用在前台时也会显示提醒；设置页区分持续提醒、临时横幅、已授权但未开启桌面提醒及无法确认的样式，从系统设置返回后刷新。首次允许通知后，若尚未开启持续提醒，会展示一次设置引导；沿用旧版已显示记录，也可从“持久通知…”手动打开。已开启持续通知时隐藏该入口。测试通知与自动提醒使用同一发送通道，发送失败会保留错误提示。未打包的开发进程不能测试 macOS 通知，请使用应用包。

恢复通知只依据同一账号、同一额度窗口的真实用量从非零恢复到零触发；启动时已满额、显示舍入和倒计时归零均不会触发。通知按账号与窗口跨重启去重，关闭通知期间仍更新基线，重新开启不会补发旧事件。两次轮询之间发生且已再次消耗的恢复可能无法观察到。

重置卡到期提醒与额度重置前提醒分别设置，默认关闭。开启后可按天、小时或分钟添加、编辑和删除提前时间，例如提前 1 天、5 小时和 2 小时；每个有效时间点最多提醒一次，相同时间不能重复。重置卡默认提前 1 天，兼容已有开关与提醒记录；额度默认提前 2 小时。额度提醒仅在接口返回明确的未来重置时间且仍有剩余额度时发送，通知包含额度窗口、剩余百分比与重置时间；提前时间须短于对应额度窗口时长。

两类提醒都在成功刷新后检查，实际提醒时间受刷新间隔、休眠和网络状态影响；应用退出后不发送。每个时间点按账号、卡片或额度窗口及对应到期 / 重置时间跨重启去重。错过多个时间点时，同一张卡或同一窗口只提醒当前最近的一次；同次刷新的多张卡或多个窗口合并通知。关闭通知期间仍更新记录，重新开启不补发已观测到的旧提醒；失败或过期数据不触发。重置卡仅提醒仍可用且有到期明细的卡，不推测缺失信息。卡片到期标识随本地时间更新；可用数量仍以接口快照为准，不由本地推算改写。应用不使用重置卡。

额度页展示 [AIHOT](https://aihot.news/codex-reset) 的公开重置动态，约每 10 分钟查询，独立遵守缓存与 `Retry-After`。动态展示适用范围，以“预告”和“AIHOT 估计”区分时间来源。公告不表示当前账号已经恢复，不改写个人额度或倒计时。预告过期后仍需确认，首次读取只建立通知基线。数据使用遵循 [AIHOT 使用条款](https://aihot.news/terms)。

应用包含当前版本更新说明时，该版本首次打开会展示，关闭后保存已读版本。设置中的新版说明与首次展示共用 Markdown 排版，支持标题、列表、链接和折叠说明，自动隐藏 GitHub 生成的注释；没有随包说明的本地构建不显示空弹窗。

## 统计口径与数据

默认读取 `~/.codex/sessions` 和 `~/.codex/archived_sessions`，Windows 的 `~` 为当前用户目录；`CODEX_HOME` 可覆盖。支持 `.jsonl` 与 `.jsonl.zst`，压缩日志按块解码，不生成解压文件。

- 按日志中的 `last_token_usage` 统计，使用累计签名去重；普通 / 压缩副本、归档迁移、分段和 fork 重放不会重复计数。缺少逐次用量的旧事件不从累计值倒推。
- 总 Tokens = 新增输入 + 输出 + 缓存命中 + 缓存写入。输入已扣除缓存，不重复加上推理 Token。缓存命中率分母为全部输入（含缓存），分母为零显示不可用。
- 费用以 Rust `Decimal` 逐项计算，是美元 API 等价估算，**不代表订阅账单**。价格未知与真实零价分开；部分缺价显示“已定价费用”，完全缺价显示“未定价”。统计范围内含未定价记录时，所有分组的费用占比显示“—”，不把已定价部分视为完整费用；Tokens 占比照常计算。
- 内置 [models.dev](https://models.dev) 的 OpenAI 文字模型价格快照，支持公开价格更新和自定义价格。定价列表自动合并日志中出现的模型，已知别名沿用实际计价规则，未知模型可直接补价；自定义值优先，空白表示未知，`0` 表示免费；价格变更重新计算历史，不保存价格版本。
- 长上下文倍率按单条请求全部输入判定。未知计费档位不按 Standard 猜测；缺少档位的旧记录按 Standard 估算；没有明确报告来源时，包括旧历史字段缺失或 null，均显示“Standard（估算）”。
- 速度与首字为日志边界估算，带 `≈`；缺少可靠依据显示 `—`。缓存写入缺失不伪装成零。记录数指解析出的用量事件数，不代表全部网络请求数。

本机统计包含现存日志与已采集历史，可能包含多个账号，不代表当前账号或其他设备的全部用量。应用只保存统计所需元数据，不保存消息正文、浏览器 Cookie 或登录 token。

| 平台 | 应用数据目录 |
| --- | --- |
| macOS | `~/Library/Application Support/CodexQuotaDock/` |
| Windows | `%APPDATA%\CodexQuotaDock\` |

`usage-history.json` 沿用旧版格式，保留旧服务历史；当前只采集与展示 Codex。设置、额度趋势、通知基线及冷却时间保存在同一应用数据目录中。读取损坏或未知版本的数据时保留原文件并提示，不按空数据覆盖。

“重新扫描日志”清空内存扫描缓存、保留已保存历史；“清除已保存历史”经确认后只清除本应用的 Codex 历史，现存日志可再次采集，不删除源日志、其他服务旧记录或模型定价。

## 开发与构建

需要 Node.js 22.12+、项目指定版本的 pnpm、Rust stable（至少 1.90），以及 [Tauri 平台构建依赖](https://v2.tauri.app/start/prerequisites/)。macOS 安装 Xcode Command Line Tools；Windows 安装 Visual Studio C++ Build Tools 与 Windows SDK。Windows 命令行可使用 PowerShell，`.sh` 入口需要 Git Bash。

```sh
pnpm install --frozen-lockfile
pnpm tauri dev
```

只预览前端：

```sh
pnpm dev
```

浏览器不能访问桌面进程与本机数据。显式加 `?preview` 可查看标注为离线预览的匿名示例，不会连接真实 Codex。

原生窗口离线验收需同时开启预览模式并使用新的空数据目录：

```sh
CODEX_QUOTA_PREVIEW=1 CODEX_QUOTA_DATA_DIR="$PWD/work/native-preview" pnpm tauri dev
```

`CODEX_QUOTA_PREVIEW` 停止监测和日志扫描，`CODEX_QUOTA_DATA_DIR` 隔离设置与历史并跳过旧偏好导入，两者配合避免读取真实账号或历史。验收结束后退出应用并删除本次临时目录；正常启动不设置这两个变量。

macOS 与 Windows 共用 `node scripts/build.mjs`，安装包输出到 `dist/`。构建依赖、架构参数、产物名称和 CI 打包入口统一维护在 [打包、更新与发布](docs/updating.md#本地打包)。

最小验证：

```sh
bash scripts/test.sh
```

`scripts/test.sh` 已包含 `pnpm build`（TypeScript 检查与 Vite 构建）和 `cargo check --locked`，无需在它之前重复执行。在 macOS 还会运行保留的 Swift 核心与应用检查；这些检查验证旧实现，是迁移规则的基线，不能当成新 Rust 实现的自动化测试。Windows 可在 Git Bash 执行此入口，PowerShell 命令见 [验证说明](docs/updating.md#验证)。`.github/workflows/check.yml` 编译 Apple Silicon、Intel 和 Windows 目标。

生产入口为 `src/`、`src-tauri/`、`crates/quota-core/`；`Sources/`、`Tests/` 和 `Package.swift` 暂留作旧版行为参考与检查，不参与 Tauri 应用构建。旧打包工具归档到 `scripts/legacy/`，说明与验收记录见 [Swift / Sparkle 历史流程](docs/archive/updating-sparkle.md)。

### 图标再生成

应用图标的源为 `scripts/make-icon.swift`。在 macOS 先生成 1024 像素 PNG，再由项目锁定的 Tauri CLI 转为平台图标；托盘源为 `src-tauri/icons/tray.svg`，同样通过官方 CLI 生成 PNG。只修改这些源文件，不手工编辑 PNG、ICNS 或 ICO。

```sh
swift scripts/make-icon.swift work/app-icon.iconset
pnpm tauri icon work/app-icon.iconset/icon_512x512@2x.png --output work/app-icons
cp work/app-icons/32x32.png work/app-icons/128x128.png work/app-icons/128x128@2x.png work/app-icons/icon.icns work/app-icons/icon.ico src-tauri/icons/
pnpm tauri icon src-tauri/icons/tray.svg --png 32 --output work/tray-icons
cp work/tray-icons/32x32.png src-tauri/icons/tray.png
swift scripts/make-icon.swift work/dark-app-icon.iconset dark
cp work/dark-app-icon.iconset/icon_512x512@2x.png src-tauri/icons/dock-dark.png
```

生成后清理 `work/app-icon.iconset`、`work/app-icons`、`work/tray-icons` 和 `work/dark-app-icon.iconset`。托盘使用独立的单色图形，不从带背景的应用图标裁切。

发布流程与签名配置统一见 [打包、更新与发布](docs/updating.md)。第三方来源与许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
