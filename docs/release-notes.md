适用于 macOS 13+（Apple Silicon / Intel）与 Windows 10 / 11 x64。macOS 使用对应架构的 DMG；Windows 使用 NSIS 安装器，缺少 Microsoft Edge WebView2 Runtime 时由安装器引导安装。

从旧 Swift / Sparkle 版升级：退出旧应用，手动安装一次本版本。设置与用量历史保留；后续版本使用 Tauri 应用内更新。旧版 appcast 不用于安装 Tauri 更新包。

更新包签名不等同于 Apple 公证或 Windows 代码签名。当前发行配置未提供这些平台证书，首次运行时系统可能要求确认来源。

**macOS 首次打开被阻止**：如果提示“无法验证开发者”或“Apple 无法检查其是否包含恶意软件”，确认应用来自本仓库后：

1. 打开 DMG，将应用拖入“应用程序”，尝试启动并关闭拦截提示。
2. 打开“系统设置 → 隐私与安全性”，向下找到该应用，点击“仍要打开”。
3. 按系统提示确认，再点击“打开”。后续可正常启动。

详见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

<details>
<summary>备用方式：通过终端打开</summary>

确认应用来自本仓库且已放入 `/Applications` 后，在终端执行：

```bash
xattr -dr com.apple.quarantine "/Applications/Codex Quota.app"
open "/Applications/Codex Quota.app"
```

这只移除该应用的下载隔离标记，不代表已通过 Apple 公证。如果安装在其他目录，请替换命令中的应用路径。

</details>
