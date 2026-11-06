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

`scripts/test.sh` 已包含 `pnpm build`（TypeScript 检查与 Vite 构建）和 `cargo check --locked`，无需在它之前重复执行。在 macOS 还会运行保留的 Swift 核心与应用检查；这些检查验证旧实现，是迁移规则的基线，不能当成新 Rust 实现的自动化测试。Windows 可在 Git Bash 执行此入口，PowerShell 命令见 [验证说明](updating.md#验证)。`.github/workflows/check.yml` 编译 Apple Silicon、Intel 和 Windows 目标。

生产入口为 `src/`、`src-tauri/`、`crates/quota-core/`；`Sources/`、`Tests/` 和 `Package.swift` 暂留作旧版行为参考与检查，不参与 Tauri 应用构建。旧打包工具归档到 `scripts/legacy/`，说明与验收记录见 [Swift / Sparkle 历史流程](archive/updating-sparkle.md)。

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
