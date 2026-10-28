# Codex Quota Dock

在一个 macOS 原生窗口中查看 AI 编程服务的剩余额度、Token 用量和费用，额度恢复时收到通知。支持 Codex、Claude Code、Antigravity 和 Cursor，也可在菜单栏显示剩余百分比。

[下载最新版](https://github.com/sunpm/codex-quota-dock/releases/latest) · [更新记录](https://github.com/sunpm/codex-quota-dock/releases) · [反馈问题](https://github.com/sunpm/codex-quota-dock/issues)

![四个服务的额度、进度与重置倒计时](docs/images/quota.png)

*界面预览由当前源码的原生组件渲染，使用示例数据，不含真实账号或用量。*

## 支持的服务

| 服务 | 剩余额度 | 用量历史 | 费用来源 |
| --- | --- | --- | --- |
| Codex | 通过已登录的 Codex 查询 | 本机普通及压缩会话日志 | API 等价估算 |
| Claude Code | 通过已有 OAuth 登录态查询 | 本机会话及子代理日志 | API 等价估算 |
| Antigravity | 通过运行中的 IDE 查询 | 本机 IDE / CLI 导出的 transcript | 自定义模型价格的 API 等价估算 |
| Cursor | 通过已有客户端登录态查询 | 当前账号全设备的服务端记录 | Cursor 返回的费用 |

本机日志统计与 Cursor 账号统计分开展示。“全部”汇总本机 Codex / Claude Code / Antigravity 用量；选择“Cursor → 概览”查看账号用量。发行版包含的功能以对应更新记录为准。

## 安装

需要 **macOS 13 或更新版本**。

1. 从 [Releases](https://github.com/sunpm/codex-quota-dock/releases/latest) 下载安装包：M 系列芯片选 `AppleSilicon.dmg`，Intel 芯片选 `Intel.dmg`。
2. 打开 DMG，将应用拖入 `Applications`，再从“应用程序”启动。
3. 在需要监测的客户端中登录；Antigravity 需保持运行。在本应用设置中关闭不需要的服务。

当前安装包使用 ad-hoc 签名，尚未进行 Developer ID 签名与 Apple 公证，macOS 可能阻止首次打开。Release 同时提供 `SHA256SUMS.txt`。

## 日常使用

- **查看额度**：按 Codex、Claude Code、Antigravity、Cursor 顺序连续展示，随窗口宽度自动排列；每 30 秒查询已启用服务，分别显示更新时间与错误。倒计时在本地计算；失败保留上次读数并标明过期，手动刷新也遵守服务端限流。
- **菜单栏**：可选择是否显示，以及显示哪些服务；点击打开主窗口。隐藏菜单栏不影响后台监测。
- **恢复提醒**：首次启动允许通知后，可在“设置 → 恢复通知”发送测试通知或开启持久通知引导。macOS 26 及更新版本在系统通知设置中开启桌面提醒并选择“持续”，旧版选择“提醒”。
- **重置动态**：额度页的全部服务额度之后，独立显示最近三条 Tibo 重置或发卡动态，数据来自 [AIHOT](https://aihot.news/codex-reset)，每 10 分钟查询。可在“设置 → 恢复通知”开启独立的“Codex 重置动态通知”（默认关闭），点击通知打开原帖。
- **后台运行**：关闭窗口后继续监测，点击 Dock 图标可恢复窗口。需要开机启动时，在设置中开启“登录 Mac 时启动”。

| 快捷键 | 操作 |
| --- | --- |
| `⌘R` | 刷新当前页面 |
| `⌘,` | 打开设置 |
| `⌘W` / `⌘M` | 关闭 / 最小化窗口 |
| `⌘Q` | 退出应用并停止监测 |

<details>
<summary>服务与通知设置预览</summary>

![服务监测、菜单栏、恢复通知与用量历史设置](docs/images/settings.png)

使用示例状态。监测、通知和菜单栏显示可分别控制。

</details>

提醒依据同一服务、账号和额度窗口的真实用量从非零恢复到零触发，并跨重启去重。启动时已经满额、显示舍入或倒计时归零不会触发通知；关闭提醒期间仍更新观测基线，不会在重新开启后补发旧事件。若额度在两次轮询之间恢复后又被使用，可能无法观察到恢复。

重置动态属于公开公告，不代表当前账号已恢复，也不会改写额度百分比或个人倒计时。预告超过预计时间仍未获确认时标为“已过预计时间，未确认”；发放重置卡不等于已使用重置卡。原帖日期和来源核实时间按 Mac 本地时区显示，当天的原帖时间使用主文字色并加粗，预告时间保留 AIHOT 返回的时区标注。首次读取仅建立基线，之后新预告与确认分别提醒；超过 24 小时的旧帖只展示。通知去重跨重启保存，关闭动态通知期间仍消费事件；关闭 Codex 监测同时停止动态查询，再开启先重新建立基线。

动态快照、缓存标识、通知去重和下次请求时间保存在本应用 UserDefaults 中，不含账号凭据。手动刷新与重启也遵守 10 分钟间隔及 `Retry-After`；睡眠暂停，唤醒后到期再读取。失败保留上次快照，来源延迟或过期会单独标明，最新成功快照会替换旧列表以应用上游更正或撤回。AIHOT 是独立第三方数据服务，接口与数据使用遵循其[使用条款](https://aihot.news/terms)，不适用本项目或其框架仓库的代码许可。

## 用量统计

### 本机 Codex / Claude Code / Antigravity

- **概览**：总 Tokens、估算费用、对话数、缓存命中率、当前范围的趋势、用量构成和高消耗对话。最近 53 周热力图在下方独立展示，不受当前日期范围影响，保留自己的指标切换。
- **时间范围**：今天、昨天、最近 7 / 30 个自然日、全部及自定义日期，按 Mac 本地时区统计。今天和昨天显示小时趋势，较长范围显示每日趋势；顶部 Tokens / 费用切换共同控制趋势指标、排名与表格排序和占比，支持悬停明细。
- **同期比较**：Tokens 与费用对比前一个等长期间，进行中的范围对齐当地截止时刻；“全部”不比较。上期为零显示新增量，费用含未定价记录时不计算涨跌。
- **对话明细**：点击对话名称查看逐条时间、模型、Token 分类、速度档位与费用，并汇总 Standard / Fast / Ultrafast。汇总表使用原生表格，可调整列宽，长名称可悬停查看。Codex 同一线程的分段日志归为一个对话，独立 fork 仍分开。记录数是已解析的用量事件数，不代表全部网络请求数。
- **项目汇总**：可确认的 Git worktree 与子目录归入主仓库，原始工作目录仍保留在明细中；子模块保持独立，无法确认归属时不按目录名猜测。

本地统计包含现存日志与已采集历史，可能合并本机多个账号，不代表当前账号或其他设备的全部用量。面板可见时每 30 秒扫描，也可手动刷新；只读取本地文件，不请求服务接口，关闭窗口后暂停轮询。

Antigravity 只统计 IDE / CLI 导出的 `transcript_full.jsonl` 中已完成且包含有效输入、输出计数的响应。两处目录按会话与步骤合并，旧会话追加和步骤计数修正会更新；重复副本不累计，重叠步骤采用较新文件的计数。缺少计数的响应提示统计不完整，不从正文估算；仅有原生数据库、未导出 transcript 的历史暂不支持。

模型只取响应自身字段，缺失时显示“未知模型”；不解析正文中的模型切换，也不读取原生数据库补全。项目归属暂显示未知。Antigravity 价格可在“设置 → 模型定价”添加，缺价时保留“未定价 / 部分”，不使用其他服务的价格代替。

### Cursor 账号用量

在“Cursor → 概览”查看当前账号全设备的 **Token、请求数、模型汇总和服务端费用**。默认最近 30 个自然日，可选择开始与结束日期；可查询历史以接口实际返回为准。接口没有可确认的项目或会话归属，因此“对话”和“项目”导航不可用；从这两页切换到 Cursor 时自动进入概览。

费用来自 `chargedCents`，按美分换算为 USD，可能包含套餐内用量，**不等于额外账单**。缺失费用与零费用分别显示；Token 分类不完整时标明未知或部分，不用本地模型价格补算。

仅在 Cursor 监测已启用且概览可见时自动查询，成功后间隔五分钟。完整分页成功后替换快照，失败保留上次成功的范围、数据与时间并标记过期；超过查询上限时提示缩小日期范围。401 / 403 或取消钥匙串授权后等待手动重试，刷新不会绕过与 Cursor 额度查询共用的限流冷却。

账号变化或关闭 Cursor 监测时清空旧快照，睡眠与退出取消在途查询。远端历史只保留在内存，重新打开应用后按需查询。

### 费用与模型定价

本机日志的费用是 **API 等价估算**，以 USD 展示，不代表订阅账单。缺价时显示“未定价”或“部分”，不会算作免费。

内置 [models.dev](https://models.dev) 的文字模型价格快照，离线可用。在“设置 → 模型定价”可更新公开价格、搜索或添加模型，并调整单价、速度倍率和长上下文阈值。自定义价格优先；空白代表未知，`0` 代表免费。价格变化会重算已采集历史，不保存历史价格版本。

<details>
<summary>日志路径与统计口径</summary>

| 服务 | 默认位置 | 自定义目录 |
| --- | --- | --- |
| Codex | `~/.codex/sessions`、`archived_sessions` | 启动时传入 `CODEX_HOME` |
| Claude Code | `~/.claude/projects`，包含子目录 | 启动时传入 `CLAUDE_CONFIG_DIR` |
| Antigravity | `~/.gemini/antigravity/brain` 与 `~/.gemini/antigravity-cli/brain` 下各会话的 `.system_generated/logs/transcript_full.jsonl` | 暂不支持自定义目录 |

- Codex 支持 `.jsonl` 和 `.jsonl.zst`，压缩日志按块解码，不生成解压文件；普通与压缩副本、归档迁移和 fork 重放使用同一去重规则。`<线程 ID>_<分段 ID>` 文件名与首条元数据一致时，分段归入原线程，并在扫描时纠正已有历史的对话归属；源日志已删除且无法确认的历史保持原归属。按 `last_token_usage` 统计，累计签名用于去重；缺少该字段的旧事件不从累计值倒推。
- Claude Code 同一消息与请求的流式快照保留最大完整用量；输出为零但输入有消耗的记录仍计入。Claude 压缩日志暂未支持，会提示统计不完整。
- Antigravity 的 `input_tokens` 已排除缓存，`output_tokens` 已含推理 Token；缓存读取与写入单独计入，不重复扣减或累加。输入或输出计数缺失时不入账；缓存字段未导出按零处理，显式无效计数会跳过并提示。只记录 `PLANNER_RESPONSE` 的 `DONE` 状态，同一步骤使用最后一次导出结果。
- 总 Tokens = 新增输入 + 输出 + 缓存读取 + 缓存写入。缓存命中率 = 缓存读取 ÷ 全部输入（含缓存），分母为零显示不可用。Codex 输入已扣除缓存，输出不重复加上推理 Token。
- 费用使用 `Decimal` 分项计算：各类 Token × 每百万单价 ÷ 1,000,000。Claude 一小时缓存写入采用独立单价；长上下文阈值按单条请求全部输入（含缓存）判定，不按整段对话累计量判定。
- 缺少速度的旧日志按 Standard 估算，未知档位保留未定价。缺少缓存保留期时沿用短期缓存估算，不推断缺失的长保留期字段。
- 保留原始模型名，只规范化已知厂商前缀、Claude 版本小数与日期后缀，不猜测未知别名。估算不包含订阅费、税费、折扣或工具调用附加费。

</details>

## 数据与凭据

已采集的本地用量保存在 `~/Library/Application Support/CodexQuotaDock/usage-history.json`。只保存用量、计费与项目归属所需元数据，不保存消息正文或凭据；源日志被清理后，已经采集的记录仍可查看，采集前已删除的内容无法恢复。读取失败保留原文件，保存失败保留内存结果并提示。

“设置 → 用量历史”提供两个操作：**重新扫描日志**会忽略内存文件缓存、保留历史；**清除已保存历史**经确认后仅删除本应用保存的本地历史，再从现存日志采集，不删除源日志、模型定价或其他应用数据。

额度与 Cursor 远端用量仅为已启用服务读取已有登录态，不读取浏览器 Cookie，不刷新或改写其他应用的凭据，不保存 token。首次读取 Claude / Cursor 登录态可能需要钥匙串授权；登录过期后请在对应客户端重新登录。通知去重仅保存账号标识的 SHA-256 摘要及窗口状态。

<details>
<summary>服务接口与运行边界</summary>

| 服务 | 读取方式 |
| --- | --- |
| Codex | 复用 `codex app-server` 的 `account/read` 与 `account/rateLimits/read`；优先使用桌面应用内的 CLI，可用 `CODEX_QUOTA_CLI` 指定路径 |
| Claude Code | Anthropic OAuth `profile` / `usage`；读取 `.credentials.json`，不存在时读取 `Claude Code-credentials` 钥匙串项 |
| Antigravity | 本机语言服务的 `GetUserStatus` / `RetrieveUserQuotaSummary`；自签名证书兼容仅限固定的 `127.0.0.1` 地址 |
| Cursor | `usage-summary` 与 `get-filtered-usage-events`；只读 `state.vscdb`，兼容 `Cursor Safe Storage` 加密格式 |

不创建对话、不发起模型任务，也不会自动使用额度重置券。手动更新价格只请求公开价格表，不发送会话信息。

各服务独立退避，延迟依次为 30、60、120、240、300 秒。HTTP 429 至少等待 `Retry-After`，未提供时等待 300 秒。睡眠暂停轮询，唤醒恢复；退出清理应用持有的资源。

客户端内部接口或登录格式升级后可能需要适配。Claude API Key、独立 `agy` CLI、Cursor 旧请求计数套餐及浏览器登录回退不在支持范围；没有有效额度时显示不可用。Cursor 团队共享池表示团队额度，不是个人预算。

菜单栏空间不足时 macOS 可能隐藏图标；专注模式与系统通知设置可能影响提醒。30 秒是目标查询间隔，不保证服务端数据同步更新。

</details>

## 从源码构建

需要 Apple Command Line Tools。项目采用 Swift Package、SwiftUI / AppKit，无第三方 Swift 包；Zstandard 解码源码静态编译，无需额外安装 `zstd`。

```sh
git clone https://github.com/sunpm/codex-quota-dock.git
cd codex-quota-dock
bash scripts/build.sh
open "dist/Codex Quota Dock.app"
```

应用产物位于 `dist/`。现有离线检查入口：

```sh
bash scripts/test.sh
```

检查覆盖解析、通知去重、限流、服务隔离、设置及窗口生命周期，使用模拟客户端，不读取真实凭据或调用服务接口。编译与离线检查通过不等于真实账号已连接。

<details>
<summary>打包、发布与诊断</summary>

按架构生成 DMG：

```sh
bash scripts/package-dmg.sh arm64
bash scripts/package-dmg.sh x86_64
```

脚本复用标准构建，使用系统 `hdiutil` 生成并校验镜像，产物位于 `dist/`。可通过 `APP_VERSION` 指定版本；本地默认使用源码版本与当前架构。

推送 `vX.Y.Z` 标签会触发 [Release 工作流](.github/workflows/release.yml)，在 `macos-15` / Xcode 16.4 上运行检查、分别构建 Apple Silicon / Intel DMG，并发布校验值。`-beta.1`、`-rc.1` 等后缀标记为预发布，不设为 Latest。标签版本与运行编号只写入构建产物，不回写源码元数据。

更新说明由 GitHub 原生 Release Notes 根据已合并 PR 生成，已有正式版本时从最近正式版本累计，配置见 [.github/release.yml](.github/release.yml)。发布使用 Actions 自带 `GITHUB_TOKEN` 和 `contents: write` 权限，无需额外 PAT。已发布版本使用新标签更新，不覆盖原附件；上传失败留下的未发布草稿需确认并清理后重跑。

构建后的应用提供两个可选诊断入口：

```sh
"dist/Codex Quota Dock.app/Contents/MacOS/CodexQuotaDock" --probe
"dist/Codex Quota Dock.app/Contents/MacOS/CodexQuotaDock" --render-menu-previews work/menu-previews
```

`--probe` 会使用真实 Codex 登录态查询，仅输出登录复用状态及剩余百分比；`--render-menu-previews` 使用示例数据生成菜单栏图片，不启动监测。

</details>

## 致谢

界面、日志解析和服务接入参考了 [cc-bar](https://github.com/nanvon/cc-bar)、[cc-switch](https://github.com/farion1231/cc-switch) 与 [CodexBar](https://github.com/steipete/CodexBar)；模型价格来自 [models.dev](https://models.dev)，压缩解码使用 [Zstandard](https://github.com/facebook/zstd)。来源、改编范围和许可见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，完整声明随应用分发。
