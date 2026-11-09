# 开发与构建

[返回 README](../README.md)

当前实现使用 Tauri 2、Vue 3、Rust、TypeScript、Vite、Apache ECharts 和 shadcn-vue。

## 构建要求

| 项目 | 要求 |
| --- | --- |
| Node.js | 22.12+ |
| pnpm | `package.json` 中 `engines.pnpm` 指定的范围：`>=12.11.2 <13` |
| Rust | stable，至少 1.90 |
| macOS | Xcode Command Line Tools |
| Windows | Visual Studio C++ Build Tools、Windows SDK；执行 `.sh` 入口时需要 Git Bash |

平台依赖安装方法见 [Tauri 官方说明](https://v2.tauri.app/start/prerequisites/)。以下命令均在仓库根目录执行。

pnpm 使用兼容版本范围，不自动切换到某个补丁版本；`Check` 和 `Release` 从同一个 `engines.pnpm` 字段读取安装范围。普通稳定依赖沿用 `^`，允许兼容的次版本和补丁更新；`@pmun/utils`、DOMPurify 与 Markdown 解析器采用 `~`，只允许当前次版本内的补丁更新。Rust 依赖继续沿用现有兼容范围。

`pnpm-lock.yaml` 和 `Cargo.lock` 继续记录实际解析版本，日常安装和 CI 保留 `--frozen-lockfile` / `--locked`。范围放宽不会让每次构建自动升级依赖；有意升级时使用包管理器更新锁文件，审阅差异并通过现有检查后一起提交。

## 启动开发环境

```sh
pnpm install --frozen-lockfile
pnpm tauri dev
```

只预览前端：

```sh
pnpm dev
```

浏览器不能访问桌面进程与本机数据。显式加 `?preview` 可查看标注为离线预览的匿名示例，不会连接真实 Codex 或 Antigravity。

应用版本以 `package.json` 为准，Tauri 配置与网页预览直接读取该字段。正式发版使用 `pnpm release <版本>` 同步 Cargo 版本、锁文件和 CHANGELOG；普通 PR 无需递增版本，也不会触发发布。操作步骤见 [手动发布](updating.md#手动发布)。

原生窗口离线验收需同时开启预览模式并使用新的空数据目录：

```sh
CODEX_QUOTA_PREVIEW=1 CODEX_QUOTA_DATA_DIR="$PWD/work/native-preview" pnpm tauri dev
```

`CODEX_QUOTA_PREVIEW` 停止监测和日志扫描，`CODEX_QUOTA_DATA_DIR` 隔离设置与历史并跳过旧偏好导入，两者配合避免读取真实账号或历史。验收结束后退出应用并删除本次临时目录；正常启动不设置这两个变量。

macOS 与 Windows 共用 `node scripts/build.mjs`，安装包输出到 `dist/`。构建依赖、架构参数、产物名称和 CI 打包入口统一维护在 [打包、更新与发布](updating.md#本地打包)。

最小验证：

```sh
bash scripts/test.sh
```

`scripts/test.sh` 包含 `pnpm build`（TypeScript 检查与 Vite 构建）和 `cargo check --locked`，无需在它之前重复执行；该入口执行编译检查，不代表已覆盖运行时行为。Windows 可在 Git Bash 执行此入口，PowerShell 命令见 [验证说明](updating.md#验证)。`.github/workflows/check.yml` 编译 Apple Silicon、Intel 和 Windows 目标。

生产入口为 `src/`、`src-tauri/`、`crates/quota-core/`。旧 Swift 应用、测试和打包工具已移除，历史源码与验收记录见 [Swift / Sparkle 归档](archive/updating-sparkle.md)。当前 macOS 系统集成与旧数据迁移仍由 Rust 实现，图标生成脚本继续保留。

## Antigravity CLI 接入边界

首版只使用官方 CLI 的 `agy -p /usage --output-format json`，不启动模型任务、不解析 TUI、不接入本地接口或自行获取 Google 凭据。执行前校验正式版版本：macOS 至少 1.1.11，Windows 至少 1.4.10；后者用于限定已核对的 headless 认证行为。通过 `CODEX_QUOTA_AGY`、`PATH`、用户安装目录查找原生可执行文件，Windows 只执行 `.exe`，不通过 shell、`.cmd` 或 WSL。

解析入口要求 `status=SUCCESS`、`command.name=usage`，读取 `command.data.groups` 的名称及 `buckets` 的 `id`、`name`、`window`、`remaining_fraction`、`reset_time` 和 `disabled`。分组不按模型写死；未知扩展字段可忽略，缺失或越界的比例保持未知，不能通过 clamp 伪造 0% / 100%。只有 `window=5h/weekly` 才标注具体窗口，不从名称、桶 ID 或重置日期推断。报告不提供可靠身份，因此个人额度不落盘、不参与历史和恢复提醒。

查询沿用 Rust / Tokio 子进程，每次使用私有临时工作目录，标准输入关闭，版本检查限 3 秒、额度读取限 90 秒，输出流分别限 1 MiB。所有应用启动的 `agy` 子进程收到 `AGY_CLI_DISABLE_AUTO_UPDATE=true`、`AGY_CLI_NONINTERACTIVE_HEADLESS=true`、`AGY_CLI_INTERACTIVE_HEADLESS=false`；不改写全局配置或登录存储。原始 stdout/stderr 不写日志或错误界面，stderr 只用于固定错误分类；不读取 CLI 日志文件。

macOS 使用独立进程会话，在本次临时目录中提供失败的 `open` / `xdg-open`，并设置 `BROWSER` 阻止自动浏览器登录。Windows 以 `DETACHED_PROCESS | CREATE_SUSPENDED` 创建进程，恢复执行前加入仅允许一个活动进程的 Job；不能成功建立限制时不执行查询。此限制同时禁止浏览器、MCP 与其他辅助子进程，配置了此类功能的 CLI 可能无法查询。结束、取消、休眠或退出时清理本应用拥有的进程和临时目录。

个人额度使用独立监测开关、调度、刷新状态和错误状态，共用设置中的刷新间隔。`requires_action` 错误停止自动重试，用户在终端处理后手动刷新；可识别的网络与限流失败按冷却重试。失败保留本次运行中的成功快照及时间。公开动态使用独立的 AIHOT feed、ETag、十分钟调度与通知基线，不参与个人额度恢复判定。

CLI 未在 stderr 中提供认证原因时，只能显示无法确认原因的查询失败或超时，不据此断言登录失效。CLI 没有输出 `Retry-After` 时，已识别的限流按至少 300 秒冷却。macOS 清理范围为本应用创建的进程组，不能保证清理自行脱离该进程组的辅助进程。

参考源码、许可证及已知问题见[第三方来源](../THIRD_PARTY_NOTICES.md#antigravity-额度接入)。

### 前次离线验收（2026-11-08）

本轮按用户要求只做离线实现，未查询真实账号，本机未找到官方 `agy`。在 macOS 15.7.9 x86_64 上，`pnpm build` 的 TypeScript 检查与 Vite 构建，以及 `cargo check --locked --offline --manifest-path src-tauri/Cargo.toml` 均通过。未新增或修改自动化测试，也未使用临时脚本编写测试。

Chrome 专门代理完成一次离线关键流程验收：默认额度、未知额度、保留旧数据与成功时间的过期错误、刷新中和空态均显示正确；两项服务开关经 Space、Tab、失焦操作检查，关闭 Antigravity 只禁用自身公开动态通知，关闭 Codex 后共用刷新间隔仍可操作。验收发现 Antigravity 百分比缺少“剩余”标识，修复后已复核。该结果只证明离线界面行为，不证明服务连接、认证或系统集成。

| 环境 / 范围 | 本轮结果 |
| --- | --- |
| macOS 15.7.9 x86_64 | 前端与 Rust 编译检查通过，Chrome 离线关键流程通过 |
| macOS Apple Silicon、其他 macOS 版本 | 未编译、未验收 |
| Windows x64 | 未编译、未验收 |
| 两平台真实额度与官方界面对照、登录失效的静默行为、原生菜单栏 / 托盘 | 未验收 |

界面沿用现有 `surface`、原生选择器、Switch、Button 与主题，无新增设计系统，因此不改写 `DESIGN.md` 或 `.impeccable/design.json`。工具报告的 `DESIGN.md` 比 sidecar 更新属于既有文档差异，本轮保留。Chrome 截图 API 没有文档化的落盘方式，本轮未保存截图文件。

## 本地用量接入与验收（2026-11-09）

本轮将用量范围扩展为 Codex + Antigravity；额度采集继续沿用原有 CLI 路线。产品名、仓库名与正式 Bundle ID 保持不变。

### 读取、去重与费用

`quota-core::LocalUsageReader` 继续管理同一份 `usage-history.json`、项目映射和扫描缓存，新增 Antigravity 格式适配。读取 `GEMINI_CLI_HOME` 或用户目录的 `.gemini`，扫描 `antigravity-cli` / `antigravity` 的 `brain/<会话>/.system_generated/logs/transcript_full.jsonl` 与 `conversations/<会话>.db`，兼容桌面根目录中以会话 UUID 命名的 `.db`。不扫描登录文件、配置、其他用户目录或外部导出缓存。

JSONL 仅导入已完成的 `PLANNER_RESPONSE`；同一 `step_index` 以文件内最后版本为准。原生 SQLite 只打开只读连接，在同一事务内读取 `steps`、`gen_metadata` 和项目元数据；有 WAL 时读取其已提交记录，不等待写锁。无 WAL 的已关闭数据库使用 `immutable=1`，避免创建 sidecar，读取前后核对主文件身份、大小、修改时间与 WAL 状态，变化时保留其他可读来源并报告覆盖缺口。这是本机普通只读打开已关闭 WAL 库失败后采用的上游已验证处理，不复制数据库或写入源表。

仅使用 `prost` 的小型字段声明，无构建期 Protobuf 生成器：

| 元数据 | 字段与口径 |
| --- | --- |
| 生成关联 | `steps.metadata.#20.#3` → `gen_metadata.idx`，索引零有效 |
| 模型 | JSONL 明确模型优先，其次原生 `gen_metadata.data.#1.#19`；最后采用已记录的 Model Selection 事件；无依据则 `unknown` |
| Token | 原生 `#1.#4` 的字段 2 / 3 / 5 为新增输入 / 总输出 / 缓存读取；有效 Protobuf 消息中省略的标量按其 schema 表示零。JSONL 缺失字段不会当零，可由对应原生计数补全 |
| 时间 | JSONL `created_at`，或直接关联的 `steps.metadata.#1`；独立生成只接受已确认的 `#1.#9.#4` 标准 Timestamp。没有可靠时间则不导入，不拿会话开始或文件修改时间代替 |
| 计时 | 原生 `#1.#11` 为首字耗时，`#1.#12` 为后续流耗时；显示仍带近似标识，不推断缺失计时 |
| 项目 | `trajectory_metadata_blob` 的 `workspace_uris #7`，兼容旧 `workspaces #1.#1`；仅唯一可确认的文件 URI 归属项目 |

Antigravity 输入不含缓存、输出已包含思考；这与 Codex 输入拆分的入口不同。内部继续使用归一化 `UsageTokens`，增加字段是否报告的标识，保留未知与真实零值的区别。只保留统计元数据，不保存消息正文、模型思考文本或登录凭据。

缓存以会话的 JSONL、SQLite 和 WAL 文件状态为依据；变化后重读该会话，以修正已完成步骤的重写。跨根目录按会话 UUID 与步骤去重，SQLite 独立生成按生成索引去重，建立关联后移除旧的独立生成键；纯会话索引从不占用日志候选。副本计数冲突采用最近修改来源并提示统计可能不完整，文件修改时间只用于来源选择。父会话中的代理消息、汇总和工具输出不额外累计 Token。

新记录使用 `antigravity:v2:` ID 前缀，沿用历史文件版本及 Swift epoch 存储兼容。旧版 Antigravity 记录保持原值，不自动加入统计；从可读源文件重新导入，因此不会把旧记录再加一次。清除历史按所选服务进行，包括该服务的旧记录，保留其他服务与模型定价；源文件不删除。重新扫描只失效所选服务缓存。

价格按 `service:model` 区分，复用 Rust Decimal；OpenAI / Google / Anthropic 公开文字 Token 单价和自定义价格均按服务匹配。未知模型及未确认的 `trial`、`tiered`、`high`、`-n` 等后缀不自动套价。Antigravity 按公开基准单价作 API 等价估算，不推断订阅扣费、计费档位、地区或工具附加费；原生来源未提供缓存写入时长，有写入计数时费用保持未知。公开价格更新失败保留原目录，自定义价格优先。快照与历史重算沿用现有流程，不新增历史价格版本。

### 上游与版本边界

先阅读 CC Switch #8693、#8914、#8941，再核对当前源码及 MIT 许可证：#8693 已合并，#8914 截至本次复核仍未合并；#8941 已关闭，源码中已有纯索引不遮蔽 transcript 的处理。对照 CodexBar 的本地 SQLite / 时间覆盖说明及 TokenUsageInsights 的原生项目元数据，固定源码与来源声明见 [第三方许可](../THIRD_PARTY_NOTICES.md#antigravity-本地用量)。

最低额度查询版本保持 macOS 正式版 1.1.11、Windows 原生正式版 1.4.10：前者由[官方变更说明](https://antigravity.google/docs/changelog)确认引入只读 print slash command；Windows 下限复核[已合并的 #290](https://github.com/hemsoft-dev/codexbar/pull/290)中的 headless 认证与 Job 条件。这个版本下限不代表所有历史格式都受支持。旧加密 `.pb`、未知 Protobuf 布局、缺少可靠时间或无法读取的数据明确报告未覆盖，不解密、不处理 Google 凭据、不增加本地服务导出路线。

### 本次结果与限制

| 环境 / 范围 | 结果 |
| --- | --- |
| macOS 27.2 Apple Silicon | 仓库 `scripts/test.sh` 的 TypeScript、Vite 构建与 Rust 检查通过；最终局部调整另跑类型检查与 Rust 检查，未重复前端构建 |
| 本机 Antigravity 2.29.0 原生记录 | 本次实际 Rust 桌面进程在隔离历史目录导入 324 条响应、11 会话、4 项目；全部补全原生模型与计时。多次后台扫描后仍为 324 条。新增输入 1,492,541、输出 362,001、缓存读取 17,656,799 |
| 旧历史与覆盖 | 本机 199 条旧 Antigravity 历史保留且未计入；79 份旧 `.pb` 未覆盖。Codex 与其他服务原有历史保留。本机 CLI 目录没有完整日志，因此 CLI 来源发现已实现，尚无本机 CLI 历史样本实机验收 |
| 官方 CLI 真实额度 | `agy 1.5.3` 只读查询成功。Gemini 周额度 99.928343%、五小时 100%；Claude/GPT 两桶 100%；Argon 周额度 80.242974%，与官方界面的 100% / 80% 取整显示一致 |
| 官方界面关闭后查询 | 由 Computer Use 退出本轮启动的官方 Antigravity，并确认未运行；随后独立 CLI 查询仍成功。已使用周窗口的重置时间不变，分别为 2026-11-14 16:17:25 与 15:48:56（Asia/Shanghai），符合官方界面“5 天 5 小时”提示。条件为独立 CLI 已登录、系统登录存储可访问且网络正常 |
| 一次 Chrome 离线关键流程 | 服务筛选、概览 / 明细 / 侧栏一致、来源区分、未知模型 / 价格、按服务自定义价格、按服务清除与刷新通过；新增选择器默认、聚焦、失焦与相邻控件对齐通过。CUA 原生选项菜单中方向键没有可判断结果，键盘箭头未验收 |
| 原生额度、设置持久化与正常退出 | 按准确路径操作已安装的 0.25.5，临时开启 Antigravity 后成功读取关闭官方界面时的额度；分组及两个已用周窗口时间与 CLI 一致。99.928343% 按现有向下取整规则显示 99%，官方界面显示 100%。正常 `⌘Q` 后核对无应用或 `agy` 遗留，重开后监测开关保持开启，手动读取成功；验收结束已恢复原先关闭的 Antigravity 监测，其他原设置未变，原应用保持运行 |
| 原生菜单栏状态项与菜单 | 未验收；工具的应用窗口树无法观察系统状态栏。菜单栏显示偏好已核对，不能据此宣称状态项视觉与菜单交互通过 |
| 登录失效时静默失败与停止重试 | 未验收；当前 CLI 登录有效，未为构造失败而退出账号、读取凭据或修改官方配置。现有 `requires_action` 调度逻辑保留 |
| Windows、macOS Intel 及其他系统版本 | 本轮未编译、未验收。Windows 无终端闪现和单进程 Job 对实际配置的影响均未验收 |

原安装版重启时发现：内存额度快照已丢弃，但成功轮询的下一次期限仍在持久化调度中，导致启动后等待普通间隔才自动查询。已在本次代码的启动入口修复：已开启监测且无失败退避时重置普通下一次期限；服务端限流截止时间保持不变。修复后用独立数据目录运行真实桌面代码，沿用刚刚真实查询保存的下一次期限（10:56:27）；实际在 10:53:37 已成功取数，下一次期限推进到 10:58:37，失败计数为零，确认未等待旧的普通轮询期限（均为 Asia/Shanghai）。该实机检查使用现有生产读取器，没有新增测试代码。

真实服务查询经过用户授权；没有创建模型任务或保存登录凭据。本次新代码的本地历史验收使用临时应用标识与 `CODEX_QUOTA_DATA_DIR`；现有额度接入另在已安装 0.25.5 上验收，未替换 `/Applications` 的安装。没有新增或修改自动化测试，也没有临时断言或测试夹具。已有前端构建保留 chunk 大小提示；机械界面检查无新增发现。现有设计规则继续复用，未扩展设计系统，`.impeccable/design.json` 的既有不同步状态保留。

## 通用工具方法

前端按需从 `@pmun/utils` 主入口导入，版本范围为 `~0.17.0`，当前锁文件解析为 0.17.0；该版本仅导出主入口，不使用 `/is`、`/date` 等子路径。2026-11-07 已核对[上游](https://github.com/sunpm/sunpm-utils)维护状态、issue、类型声明及发布包源码，8 类方法的适用范围如下。

| 类别 | 当前使用与取舍 |
| --- | --- |
| `is` | `isPlainObject`、`isString` 用于本地筛选偏好的读取入口；字段校验后向内传递 `UsageFilters`。`isNumber` 不排除 Infinity，不能替换价格校验的 `Number.isFinite`。 |
| `date` | `formatDate`、`startOf`、`addDays` 实现本地日期键、日界线和自然日移动。统一传入 `Date`，避开库按数字位数推断秒 / 毫秒及将 0 视为无效时间的规则。保留现有 Intl 展示、受扫描时钟控制的筛选范围，以及区分未知时间和等待重置的倒计时。 |
| `array` | `groupBy` 用于程序生成的日期 / 小时键，`sortBy` 用于逐条明细的日期降序。该版本 `groupBy` 用普通对象存储分组，模型 / 项目等外部字符串键继续使用 `Map`。`unique`、`first`、`last`、`flatten` 等与现有原生写法相近，暂不替换；树、集合和随机方法暂无对应需求。 |
| `number` | `trimDecimalZeros` 清理精确金额字符串的尾零，不经过浮点数。`formatCurrency` 仍转换为 Number，不能用于精确费用聚合；保留 BigInt 聚合和当前小额显示精度。`clamp` 可用于未来的双向限值，现有简单范围表达式保留。 |
| `object` | `deepClone` 替换价格编辑草稿的 JSON 往返拷贝，适用于当前无环的普通对象。`pick`、`omit`、`mapValues`、合并工具暂无重复业务可替换；`mergeWithDefaultModel` 不代替入口字段校验。 |
| `string` | 大小写、模板、截断和数字串解析暂无需要；`parseJsonStr` 的回退值语义不同，保留 VueUse 管理的 JSON 读取。`escapeHtml` 不能代替更新说明的 DOMPurify 清理，`isValidUrl` 也不代替 HTTPS 来源限制。 |
| `url` | 当前只读取 `preview` 查询标记，原生 `URLSearchParams.has` 已足够；暂不接入查询对象、参数追加和斜杠处理方法。 |
| `promise` | `delay`、`timeout`、`retry`、`debounce`、`throttle`、`parallel`、`sequential` 暂无前端替换点。服务轮询及 Retry-After 冷却由 Rust 管理，通用重试不参与该流程。 |

库的主入口会初始化 Day.js 中文 locale 和日期插件，新增依赖的许可随现有 `scripts/collect-licenses.mjs` 生成并打包。

## 图标再生成

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

发布流程与签名配置统一见 [打包、更新与发布](updating.md)。第三方来源与许可见 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。
