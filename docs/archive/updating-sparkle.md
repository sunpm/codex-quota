# Swift / Sparkle 历史记录

旧 Swift 应用、测试、Swift Package 配置和打包工具已从当前源码中移除。当前 macOS、Windows 构建与发布以 [updating.md](../updating.md) 为准。

## 历史源码与升级边界

迁移前的完整实现、测试、依赖许可与签名流程可从 [752a5f9 版本](https://github.com/sunpm/codex-quota/tree/752a5f9b430a39a1b42d873c08151eb845acf690) 查阅。需要复现旧版时使用该历史版本的独立检出目录和配套工具，不调用当前 Tauri 打包入口。

旧版使用 Sparkle 2.10.1、XML appcast 和 Ed25519 更新签名；历史 Release 中的安装包与 appcast 保留。旧 Sparkle 签名配置不用于 Tauri，本次源码清理未修改历史 Release、仓库 secret 或本机钥匙串。

从旧版升级仍需退出旧应用并手动安装一次 Tauri 版本。当前 Rust 实现保留原 Bundle ID、数据目录、旧偏好与历史迁移；详见 [迁移说明](../updating.md#从-swift--sparkle-版本迁移)。

## 2026-10-29 验收记录

- Intel Mac 上由 `0.99.1`（9901）经本机 HTTP 更新源升级至 `0.99.2`（9902）：点击确认后实际下载签名 DMG，由 Sparkle 安装并自动启动新版；安装后的构建号与嵌套签名校验通过。
- 额度监测关闭、刷新间隔 420 秒、动画关闭的偏好在升级后保留；临时空历史文件的 SHA256 未改变。这次没有迁移真实账号历史。
- Apple Silicon 与 Intel 均通过现有脚本构建 DMG，`generate-appcasts.py` 使用实际发行密钥为两者生成并验证签名清单。真实安装重启仅在 Intel 上执行。
- 正在运行的 `dist/` 副本进程保持不变；它与 `/Applications` 副本的主程序及 `Info.plist` 指纹均未改变。临时应用、偏好、更新源、签名缓存和导出私钥验收后清除。

以上为当时的本地验收，不代表 Tauri 更新器已完成真实升级验收。
