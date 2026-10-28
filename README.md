# Codex Quota Dock

macOS 原生额度与用量监视器，支持 Codex、Claude Code、Antigravity 和 Cursor。打开应用即可在主窗口查看统计、额度和设置，也可在菜单栏显示所选服务的剩余百分比。每 30 秒查询真实额度，各服务可独立开关监测和重置通知。

## 构建与运行

需要 macOS 13 或更新版本和 Apple Command Line Tools。请在需要监测的服务中先登录。无需第三方 Swift 包。

```sh
bash scripts/build.sh
open "dist/Codex Quota Dock.app"
```

应用启动后显示主窗口和 Dock 图标，支持 `⌘Tab` 切换。窗口可拖动、调整大小和最小化，点击外部不会关闭。红色关闭按钮或 `⌘W` 只关闭窗口，后台额度监测和通知继续运行；点击 Dock 图标、重新打开应用或点击通知均恢复同一个窗口。通过应用菜单或 `⌘Q` 完全退出并停止监测。

菜单栏是可选入口，在设置中控制是否显示以及显示哪些服务，默认开启。单击额度图标打开主窗口，右键或 Control 单击显示“打开主窗口”菜单。关闭菜单栏显示不影响监测，也不影响通过 Dock 打开窗口。

首次启动会申请通知权限。允许后可以点“测试通知”验证。已有版本的系统通知权限和 Codex 恢复去重记录继续沿用。四个服务默认开启监测和提醒，可在设置中关闭不需要的服务；首次读取 Claude / Cursor 登录态可能出现 macOS 钥匙串授权提示。

如需开机启动，建议将构建出的 `.app` 拖入“应用程序”，从新位置打开，再在控制面板的“设置”页开启“登录 Mac 时启动”。该设置默认关闭。

## 自动发布与 Changelog

推送 `vX.Y.Z` 标签后，[Release 工作流](.github/workflows/release.yml) 在 `macos-15` / Xcode 16.4 上运行现有离线检查、构建 Apple Silicon / Intel 通用应用，并发布到 GitHub Releases。`vX.Y.Z-beta.1`、`vX.Y.Z-rc.1` 等带后缀的标签会标记为预发布，不设为 Latest。

先将待发布代码及工作流提交、推送到 GitHub，再在对应提交上创建标签，例如：

```sh
git tag -a v0.7.0 -m "发布 v0.7.0"
git push origin v0.7.0
```

Release 附件包含 `CodexQuotaDock-v0.7.0-macOS-universal.zip` 和 `SHA256SUMS.txt`。Changelog 使用 GitHub 原生 Release Notes，自动汇总合并的 PR、贡献者和完整变更链接。已有正式版本时，预发布与正式版统一从当前历史中最近正式版本累计，避免遗漏 beta / rc 中的 PR；没有正式标签时由 GitHub 自动选择范围。每次改动通过 PR 合并，PR 标题简洁描述结果即可，无需添加分类标签。直接提交不保证单独列入更新条目；发布说明保存在 Releases，不自动回写仓库中的 `CHANGELOG.md`。

CI 使用标签的 `X.Y.Z` 写入应用版本、工作流运行编号写入构建号；仅修改构建产物，不改写源码中的 `Info.plist`。本地构建仍默认使用源码版本与当前机器架构，可用 `bash scripts/build.sh --arch arm64 --arch x86_64` 构建通用版本（需要完整 Xcode）。

发布使用 Actions 自带的 `GITHUB_TOKEN` 和 `contents: write` 权限，无需额外 PAT；仓库或组织策略需要允许此工作流运行。构建仍使用 ad-hoc 签名，没有接入 Developer ID 签名与公证。构建或检查失败不会发布；附件上传失败时可能留下草稿，确认原因并删除该未发布草稿后，可在 Actions 中重新运行。已发布版本使用新标签更新，不覆盖原附件。

## 主窗口与菜单栏

- 菜单栏按 Codex、Claude Code、Antigravity、Cursor 顺序显示已启用监测且勾选了“菜单栏”的服务。只显示一个服务时最多显示两个额度窗口，例如 `80%/84%`。使用系统模板图像适配深浅色和选中状态。
- 菜单栏在数据变化时更新，隐藏时停止绘制。左键打开或激活主窗口，右键显示窗口入口。秒级倒计时放在主窗口内，避免后台每秒重绘图标。
- 主窗口默认内容尺寸为 1140 × 760pt，最小 860 × 560pt。侧栏按服务筛选，提供概览、对话、项目、额度和设置；导航行整行可点击，包含图标、文字和右侧留白。顶部提供刷新；`⌘,` 直接打开同一窗口内的设置，`⌘M` 最小化，应用菜单提供关闭、编辑及窗口操作。额度页保留主额度百分比、进度和倒计时，各服务显示自己的更新时间和错误。
- 额度充足时使用中性灰，低于 20% 时为橙色，耗尽为红色。颜色仅提示状态，不改变恢复通知条件。
- 根据接口实际返回值显示额度窗口，没有第二个窗口时不补造数值。失败保留旧读数并明确提示数据过期。
- 设置页提供“在菜单栏显示额度”总开关及各服务的“监测”“重置通知”“菜单栏”开关，立即生效并持久化。菜单栏显示只控制入口和读数，不影响查询、通知或窗口内的服务列表。关闭通知仍继续查询和更新去重基线，不补发关闭期间已观察到的恢复事件；关闭监测则停止后续查询，再次开启先建立基线。系统通知权限与服务开关分开管理。
- 设置页保留测试通知、系统通知设置和登录启动开关。没有启用监测且选中显示的服务时，菜单栏入口隐藏；仍可从 Dock 打开主窗口。
- 布局和部分绘制代码改编自 [cc-bar](https://github.com/nanvon/cc-bar)，详见 [第三方来源](THIRD_PARTY_NOTICES.md)。MIT 许可声明随应用包分发。
- 主窗口与侧栏菜单样式参考 [cc-switch](https://github.com/farion1231/cc-switch)：中性选中态、紧凑导航、轻描边的设置与额度分组；继续使用系统字体、原生菜单及窗口控件。

## 本地用量统计

概览提供总 Tokens、估算费用、对话数、输入缓存命中率、用量热力图、每日用量、Token 拆分、模型/服务/项目构成和高消耗对话。侧栏可查看完整的对话与项目汇总；支持今天、昨天、最近 7 / 30 个自然日、全部及自定义日期，按 Mac 本地时区归日。对话以服务和会话 ID 标识，不读取标题索引或展示消息正文。

热力图固定展示包含本周在内的最近 53 周，周一至周日排列，跟随侧栏服务筛选；顶部日期范围继续控制汇总、每日趋势及列表。可独立切换 Tokens / 费用，移入格子立即显示日期、精确 Token 数和估算费用，移开收起；色阶按当前热力图每日最大值分为四档，无记录日期为灰色，未来日期留空。费用缺价或仅部分定价的日期显示虚线边框，悬停保留“未定价 / 部分”状态；窄窗口可横向滚动。

每日柱形图悬停时显示日期指示线及各服务的精确 Token 数、估算费用，明细浮层跟随鼠标并在边缘避让，主次随 Tokens / 费用指标切换；未定价与部分定价状态继续保留，移开图表后收起。

- **Codex**：读取 `$CODEX_HOME/sessions` 和 `archived_sessions` 的 `.jsonl`，未设置环境变量时使用 `~/.codex`。按 `last_token_usage` 统计，累计用量签名用于去除重复事件及 fork 重放；输入先扣除缓存读取和写入，输出不再重复加上推理 Token。
- **Claude Code**：读取 `$CLAUDE_CONFIG_DIR/projects` 的 `.jsonl`，默认 `~/.claude/projects`，包含子目录中的子代理记录。同一消息与请求的多次快照只计一次，保留最大完整用量；即使输出为零，有输入消耗的记录仍计入。
- **统计口径**：总 Tokens = 新增输入 + 输出 + 缓存读取 + 缓存写入；缓存命中率 = 缓存读取 ÷（新增输入 + 缓存读取 + 缓存写入），分母为零显示不可用。口径参考 [cc-switch 用量统计](https://github.com/farion1231/cc-switch/blob/main/docs/user-manual/zh/4-proxy/4.4-usage.md)。
- **刷新**：打开面板时读取，面板可见时每 30 秒刷新，也可手动刷新。后台解析，不请求服务接口；未变更文件复用内存缓存，关闭窗口后暂停日志轮询。监测开关只控制远端额度查询，本地统计独立工作。
- **范围**：仅反映本机仍保留的日志，跨账号本机记录合并统计，不代表当前登录账号或其他设备的全部用量。删除源日志后，相应用量也会从统计中消失；不额外持久化消息或用量数据库。读取失败会保留该文件本轮已有缓存并提示不完整，损坏记录与暂不支持的 `.jsonl.zst` 压缩日志会明确提示。
- **限制**：Antigravity、Cursor 目前仅提供额度查询，没有 Token 历史统计。费用为 API 等价估算，不代表订阅账单。没有 `last_token_usage` 的旧 Codex 事件不从累计值倒推；自定义目录需在启动应用时传入环境变量。

### 费用统计与模型定价

- 以 USD 展示 API 等价估算，概览、每日趋势、服务/模型/项目/对话汇总共用逐条计算结果；趋势图可切换 Tokens / 费用，列表和高消耗对话随该指标排序。价格覆盖不完整时显示“部分”，全部缺价时显示“未定价”，不补成零费用；费用占比只在选定范围全部已定价且总额大于零时展示。
- 使用 `Decimal` 分别计算新增输入、输出、缓存读取、缓存写入：各类 Token × 对应每百万单价 ÷ 1,000,000。Claude 一小时缓存写入按独立单价计算，不与五分钟混算；Codex 的缓存已经从输入中扣除，不重复收费。
- 内置 [models.dev](https://models.dev) 2026-10-28 的 OpenAI / Anthropic 文字模型价格快照，离线即可计算。在“设置 → 模型定价”可以手动更新公开价格、搜索/添加模型、编辑单价、速度倍率和长上下文阈值。更新仅请求公开价格表，不发送会话信息；失败保留旧价格，自定义价格优先并持久化。
- 长上下文按**单条请求的全部输入（含缓存）**与价格表阈值比较，不用整段对话累计量判定。已核对的 GPT-6 Astra、GPT-6.1 Sol / Terra、GPT-6 Luna 和 Claude Opus 5.5 / 5 / 4.8 Fast 倍率为 2；GPT-6 Astra、GPT-6.1 Sol Ultrafast 倍率为 6。其他未支持档位保留未定价，可填写自定义倍率。Claude 明确标注 `inference_geo: us` 时计入 1.1 倍。
- 旧日志缺少速度时按标准档估算；缺少缓存保留期明细时按短保留期估算（Claude 5 分钟、Codex 30 分钟）。当前 Codex 日志未提供可确认的 12 小时缓存写入拆分，因此不声称按该保留期精确计费。自定义价格的空白代表未知，`0` 代表免费；同一模型的更新会重算现有历史，尚未保存历史价格版本。
- 保留原始模型名，匹配时只处理已知厂商前缀、Claude 版本小数及日期后缀，不将 `codex-auto-review` 等未知别名猜成其他模型。不包含订阅费、税费、折扣或工具调用附加费，第三方渠道可自行填写价格。

计算方式参考 [cc-switch 的 CostCalculator](https://github.com/farion1231/cc-switch/blob/main/src-tauri/src/proxy/usage/calculator.rs)。速度、缓存和长上下文规则核对 [OpenAI 定价](https://developers.openai.com/api/docs/pricing)、[Claude 定价](https://platform.claude.com/docs/en/about-claude/pricing) 与 models.dev 数据。完整来源见 `THIRD_PARTY_NOTICES.md`。

## 工作方式

### 服务来源

| 服务 | 读取方式 | 前提与范围 |
| --- | --- | --- |
| Codex | 既有 `codex app-server` JSON-RPC | 使用 ChatGPT 账号登录 Codex；沿用 CLI 管理登录 |
| Claude Code | Anthropic OAuth `profile` / `usage` | 读取 `~/.claude/.credentials.json`（尊重 `CLAUDE_CONFIG_DIR`），不存在时读取 `Claude Code-credentials` 钥匙串项；显示 5 小时、7 天和接口提供的模型窗口 |
| Antigravity | 运行中的本地语言服务 `GetUserStatus` / `RetrieveUserQuotaSummary` | 需要打开并登录 Antigravity；优先显示真实分组额度，旧 IDE 回退到模型额度；不启动 `agy` 或模型任务 |
| Cursor | `cursor.com/api/usage-summary` | 只读 Cursor 的 `state.vscdb` 登录态，兼容 `cursor-safe-storage:v1` 加密格式（使用 `Cursor Safe Storage` 钥匙串）；显示接口提供的账期总额度、Auto、API 或团队共享池 |

新增客户端只为启用的服务读取现有登录态；不保存 token、不读取浏览器 Cookie、不刷新或改写其他应用的凭据。取消钥匙串访问后暂停该服务自动重试，可点击刷新再次尝试。登录过期时需在对应客户端更新登录。账号标识仅保存 SHA-256 摘要。远端请求使用临时会话；Antigravity 的自签名证书兼容仅用于固定的 `127.0.0.1` 本地地址。

### 刷新与通知

- 持有一个 `codex app-server --listen stdio://` 子进程，通过 JSON-RPC 读取 `account/read` 和 `account/rateLimits/read`。不创建对话、不发起模型任务。
- Codex 的登录凭据仍由 Codex 自己管理。优先发现桌面应用内的 CLI，其次查找 PATH、Homebrew 等位置。可用 `CODEX_QUOTA_CLI` 环境变量覆盖。
- 每 30 秒并行查询已启用服务；单个服务上一轮尚未结束时跳过触发，不积累同一服务的并发请求。菜单展开时也继续刷新。面板倒计时每秒在本地计算，不增加网络查询。
- 各服务独立按 30、60、120、240、300 秒退避，失败保留上次成功读数。HTTP 429 至少等待服务端 `Retry-After`（未提供则等待 300 秒），手动刷新也不绕过限流。唤醒后立即尝试刷新；系统睡眠期间暂停定时查询。
- 通知严格按同一服务、同一账号、同一窗口的 `usedPercent > 0 → usedPercent == 0` 判定。启动即满额不通知，恢复后重复刷新不通知，保存最近观测值以跨重启去重。各服务的通知开关独立生效。
- 本地保存账号标识的 SHA-256 摘要及各窗口用量，不存储邮箱原文。仅监测和通知，不会自动使用额度重置券。
- 显示百分比向下取整，99.9% 显示 99%，不会把四舍五入的 100% 当作真正恢复。

## 验证

```sh
bash scripts/test.sh
"dist/Codex Quota Dock.app/Contents/MacOS/CodexQuotaDock" --probe
"dist/Codex Quota Dock.app/Contents/MacOS/CodexQuotaDock" --render-menu-previews work/menu-previews
```

`--probe` 使用与应用相同的 Swift 连接代码，只输出登录复用是否成功及剩余百分比，不输出账号或凭据。

`--render-menu-previews` 使用明确的示例数据生成单窗口、双窗口、深色和异常状态的菜单栏示例图像，不启动监听，也不改动真实监测状态。

自包含测试覆盖四个服务的解析、缺失/无效数值、账期变化、Antigravity 新旧响应、通知开关、设置持久化、服务隔离、Codex 旧状态迁移、恢复去重及限流退避；仅需 Command Line Tools，不依赖完整 Xcode 或 XCTest。新增服务使用离线夹具验证，编译成功不代表已在真实账号上验证连接。

监测层检查通过注入模拟客户端验证慢请求隔离、失败保留读数、关闭服务、429、钥匙串取消和退出清理。界面检查验证菜单入口、面板复用、关闭后继续监测及重新打开；检查过程中会短暂显示示例面板。不读取真实用量日志、凭据或调用服务接口。原 `--render-previews` 仍使用旧小面板尺寸，新版统计布局通过实际窗口验收。

Swift 6.4 默认使用 `swiftbuild` 时，旧检查脚本的 `Modules` 路径不适用。核心检查仍可运行；应用检查可使用实际产物路径编译原有检查文件：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swiftc -parse-as-library -I .build/out/Products/Debug .build/out/Products/Debug/QuotaCore.o $(rg --files Sources/CodexQuotaDock -g '*.swift' | sed '/\/App.swift$/d') Tests/AppChecks/AppChecks.swift -o .build/QuotaAppChecks
.build/QuotaAppChecks
```

人工验收：启动时显示主窗口与 Dock 图标，`⌘W` 或红色按钮关闭后点击 Dock 可重新打开，`⌘M` 最小化后可从入口恢复，`⌘Tab` 可切换应用；菜单栏总开关与逐服务显示即时生效，隐藏后监测仍继续，重启确认显示偏好保留；单击菜单栏打开窗口，右键确认窗口入口可用；按需要检查真实额度、更新时间、监测及通知开关；`⌘Q` 退出后确认状态栏项目及应用拥有的 app-server 子进程结束。

## 限制

- 当前本地构建与 Releases 均使用 ad-hoc 签名，未做 Developer ID 签名或公证；下载版可能被 macOS 阻止首次打开。
- 菜单栏空间受屏幕尺寸、刘海及其他菜单项目影响；空间不足时 macOS 可能隐藏状态栏项目。
- 定时器受系统调度和网络延迟影响，30 秒是查询目标间隔，不保证服务端数据在 30 秒内更新。专注模式和系统通知设置可能影响横幅显示。
- 重置后若额度在下次轮询前已被使用，可能观察不到 100%，不会发出“恢复至 100%”通知。倒计时归零本身也不会触发通知。
- 本机 Codex CLI 的协议或登录方式升级可能需要适配。额度读取参考 [官方 App Server 文档](https://learn.chatgpt.com/docs/app-server)。
- Claude、Antigravity 和 Cursor 使用客户端内部接口或登录存储格式，升级后可能需要适配。Claude API Key、独立 `agy` CLI、Cursor 旧请求计数套餐和浏览器登录回退不在本次支持范围；没有有效百分比时显示不可用，不伪造满额。Cursor 团队共享池表示团队额度，不是个人预算。
- 查询仅调用额度/身份接口，不发起模型任务。服务联调需在本机运行构建后的应用完成。
