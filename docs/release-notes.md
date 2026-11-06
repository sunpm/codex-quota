适用于 macOS 13+（Apple Silicon / Intel）与 Windows 10 / 11 x64。macOS 使用对应架构的 DMG；Windows 使用 NSIS 安装器，缺少 Microsoft Edge WebView2 Runtime 时由安装器引导安装。

从旧 Swift / Sparkle 版升级：退出旧应用，手动安装一次本版本。设置与用量历史保留；后续版本使用 Tauri 应用内更新。旧版 appcast 不用于安装 Tauri 更新包。

更新包签名不等同于 Apple 公证或 Windows 代码签名。当前发行配置未提供这些平台证书，首次运行时系统可能要求确认来源。
