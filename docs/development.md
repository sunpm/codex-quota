# 开发与构建

[返回 README](../README.md)

当前实现使用 Tauri 2、Vue 3、Rust、TypeScript、Vite、Apache ECharts 和 shadcn-vue。

## 构建要求

| 项目 | 要求 |
| --- | --- |
| Node.js | 22.12+ |
| pnpm | `package.json` 中 `packageManager` 指定的版本 |
| Rust | stable，至少 1.90 |
| macOS | Xcode Command Line Tools |
| Windows | Visual Studio C++ Build Tools、Windows SDK；执行 `.sh` 入口时需要 Git Bash |

平台依赖安装方法见 [Tauri 官方说明](https://v2.tauri.app/start/prerequisites/)。以下命令均在仓库根目录执行。

## 启动开发环境

```sh
pnpm install --frozen-lockfile
pnpm tauri dev
```

只预览前端：

```sh
pnpm dev
```

浏览器不能访问桌面进程与本机数据。显式加 `?preview` 可查看标注为离线预览的匿名示例，不会连接真实 Codex。

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

## 通用工具方法

前端按需从 `@pmun/utils` 主入口导入，固定为 0.17.0；该版本仅导出主入口，不使用 `/is`、`/date` 等子路径。2026-11-07 已核对[上游](https://github.com/sunpm/sunpm-utils)维护状态、issue、类型声明及发布包源码，8 类方法的适用范围如下。

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
