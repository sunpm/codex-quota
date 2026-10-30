# 应用内更新与发布

应用通过 Swift Package Manager 固定接入 Sparkle 2.10.1。自动检查默认开启，每天检查正式版；自动下载安装关闭，用户确认“下载并安装”后才下载、验证并重启。已有 `updates.automaticallyChecks` 偏好继续沿用。更新只替换应用包，设置及历史仍位于原来的持久化位置。

## 更新源

两个架构使用独立清单，均作为 GitHub Release 附件托管：

- Apple Silicon：`https://github.com/sunpm/codex-quota/releases/latest/download/appcast-AppleSilicon.xml`
- Intel：`https://github.com/sunpm/codex-quota/releases/latest/download/appcast-Intel.xml`

清单指向该版本的固定标签 DMG 地址。Rosetta 下优先选择 Apple Silicon 清单。最低系统版本继续为 macOS 13，正式版本用递增的 `CFBundleVersion` 比较，显示版本使用 `CFBundleShortVersionString`。CI 用 `GITHUB_RUN_NUMBER` 作为构建号，不要重置后复用较小构建号。

更新说明使用与应用包内 `ReleaseNotes.md` 相同的内容，通过官方 `generate_appcast --embed-release-notes` 嵌入清单的 Markdown `description` 并随清单签名。应用发现新版后直接在软件更新卡片中展示，长内容可滚动查看；不另行请求 GitHub API 或下载说明。旧清单缺少说明时保留发布页入口，没有新版时隐藏说明区域；新版首次启动的说明弹窗继续保留。

预发布标签仍生成各自的签名包及清单，但发布为 prerelease，不改变 `latest`；默认自动检查不会安装预发布版本。最初未含 Sparkle 的旧版本仍需手动安装一次含更新器的版本。

## 一次性签名配置

更新签名与 Apple Developer ID 签名、公证是两件事。当前继续采用 ad-hoc 应用签名，Sparkle 的 Ed25519 密钥用于验证发布来源，不能替代 Apple 公证或首次安装的系统放行。

维护者授权后，在可信 Mac 上执行 `swift package --disable-sandbox resolve`，使用该依赖自带的 `generate_keys` 管理本项目独立密钥：

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account codex-quota
```

工具把私钥保存在登录钥匙串，并显示公钥。将公钥配置为 GitHub Actions repository variable `SPARKLE_PUBLIC_ED_KEY`。私钥通过工具的 `-x` 选项导出到仓库外的受限临时文件，再通过 GitHub 的 secret 输入方式保存为 `SPARKLE_PRIVATE_ED_KEY`；完成后删除临时文件。不要将私钥粘贴进命令参数、聊天、日志或版本库。私钥应安全备份，不能每次发行都重新生成；失去私钥会使现有 ad-hoc 版本无法验证后续更新。

本地构建用 `SPARKLE_PUBLIC_ED_KEY` 环境变量注入公钥。未提供公钥的普通开发构建仍能编译，但应用内更新不可用；带 `RELEASE_TAG` 的发行构建必须有公钥。发布流水线在缺少公钥或私钥时立即停止。

已于 2026-10-29 配置本项目独立的 `codex-quota` 钥匙串密钥，以及仓库的上述 variable 和 secret。私钥的临时导出副本已删除。后续本地签名复用该钥匙串账号，不要重新生成或替换发行密钥。可直接读取公钥用于本地构建：

```bash
SPARKLE_PUBLIC_ED_KEY="$(.build/artifacts/sparkle/Sparkle/bin/generate_keys --account codex-quota -p)" \
  bash scripts/build.sh
```

构建脚本会覆盖仓库的 `dist/Codex Quota.app`；如果正在运行的是该副本，应在独立的临时源码目录构建。

## 构建与发行

`bash scripts/build.sh` 仍是应用构建入口。它嵌入完整 Sparkle.framework 和安装助手，并按照嵌套关系从内到外 ad-hoc 签名；`bash scripts/package-dmg.sh arm64|x86_64` 继续生成两种 DMG。

现有 Release workflow 按顺序完成：

1. 运行已有检查，按 GitHub 原生 Release Notes 生成说明。
2. 构建两个架构，写入同一公钥、递增构建号和对应更新源。
3. `scripts/generate-appcasts.py --release-notes "$RELEASE_NOTES_FILE"` 调用锁定版本的官方 `generate_appcast`，分别从最终 DMG 生成包含更新说明的签名清单；说明文件须为当前版本的非空 UTF-8 Markdown。官方工具仅在包内公钥与发布私钥匹配时生成更新包签名；脚本检查该签名、版本、文件大小、下载地址及嵌入说明，再使用官方 `sign_update --verify` 验证 DMG 和清单。
4. 私钥只通过标准输入传递给签名工具，不写入命令参数或子进程环境。
5. 将两个 DMG、两个 appcast 和 `SHA256SUMS.txt` 全部上传到 draft Release，上传成功后才公开发布。签名后的 DMG 与 XML 不得再修改。

首次接入或调整更新流程时，应在临时安装目录，用两个具有不同构建号、相同公钥的包完成一次真实升级验收；检查用户确认、下载、安装、重启与原设置/历史延续。不要替换 `/Applications` 中正在使用的安装。编译和签名验证本身不代表已完成真实升级验证。

验收副本可在包内设置独立的 `SUFeedURL`，更新器默认遵循此值；只有 Rosetta 下的正式 Intel 更新源会自动切换至 Apple Silicon。为避免触及在用应用的进程、偏好与历史，验收包使用独立 Bundle ID，并通过仅写入验收包的 `LSEnvironment.CFFIXED_USER_HOME` 指向临时用户目录；原始源码与正式包不加入这些隔离设置。

`CFFIXED_USER_HOME` 不隔离系统偏好服务，也不改变 Codex 子进程的登录态查找。在首次启动前，必须用 `defaults import <验收 Bundle ID> <偏好 plist>` 向独立偏好域写入 `service.codex.enabled = false`。仅在临时目录放一个偏好 plist 不会生效。验收后删除独立偏好域与临时应用的数据。

### 2026-10-29 验收记录

- Intel Mac 上由 `0.99.1`（9901）经本机 HTTP 更新源升级至 `0.99.2`（9902）：点击确认后实际下载签名 DMG，由 Sparkle 安装并自动启动新版；安装后的构建号与嵌套签名校验通过。
- 额度监测关闭、刷新间隔 420 秒、动画关闭的偏好在升级后保留；临时空历史文件的 SHA256 未改变。这次没有迁移真实账号历史。
- Apple Silicon 与 Intel 均通过现有脚本构建 DMG，`generate-appcasts.py` 使用实际发行密钥为两者生成并验证签名清单。真实安装重启仅在 Intel 上执行。
- 正在运行的 `dist/` 副本进程保持不变；它与 `/Applications` 副本的主程序及 `Info.plist` 指纹均未改变。临时应用、偏好、更新源、签名缓存和导出私钥验收后清除。

以上为本地验收，未创建版本标签或发布 Release；GitHub Actions 的远端签名配置已保存，发布工作流须随代码提交、推送后才会采用新流程。

参考：[Sparkle 文档](https://sparkle-project.org/documentation/)、[cc-bar 更新器](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/Core/AppUpdater.swift)、[cc-bar 构建流程](https://github.com/nanvon/cc-bar/blob/530ef49f3b5808e268181a55311e0c83cc40adff/scripts/build.sh)。
