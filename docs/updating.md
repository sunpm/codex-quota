# 应用内更新与发布

跨平台版本使用 Tauri 2 updater，在 macOS 和 Windows 上检查、下载、验签、安装与重启。默认每天检查最新正式版；用户确认安装后才下载与安装，后台检查不自行安装。更新保留原有设置与用量历史。

## 从 Swift / Sparkle 版本迁移

旧版使用 Sparkle XML appcast，新版使用 Tauri 的 JSON 清单与 minisign 更新签名。**需要退出旧版并手动安装一次 Tauri 版本。** 不把 Tauri `.app.tar.gz` 或 Windows 安装器写进旧 Sparkle 清单，也不假定两套密钥可互换。

保留 Bundle ID `local.codexquotadock.app`、`CodexQuotaDock` 数据目录及旧偏好键。首次启动从 macOS 原偏好域导入设置、定价、额度趋势与通知基线，旧偏好域和原始 Codex 登录态不被改写。已采集用量继续使用原历史文件。

历史 Release 中的 Sparkle 包和 appcast 保留；新 Release 不生成 Sparkle appcast。旧客户端因最新 Release 不含旧清单而无法自动更新时，应从发布页手动安装。后续 Tauri 版本通过 `latest.json` 更新。旧版签名配置与 2026-10-29 的实际验收记录单独保留在 [updating-sparkle.md](updating-sparkle.md)，不适用于新更新器。

## 更新清单与安装包

正式更新源为 `https://github.com/sunpm/codex-quota/releases/latest/download/latest.json`。清单包含版本、说明、时间，以及三个平台的固定标签下载地址和签名：

| 平台键 | 更新包 | 首次安装 |
| --- | --- | --- |
| `darwin-aarch64` | `CodexQuota-macOS-AppleSilicon.app.tar.gz` | Apple Silicon DMG |
| `darwin-x86_64` | `CodexQuota-macOS-Intel.app.tar.gz` | Intel DMG |
| `windows-x86_64` | `CodexQuota-Windows-x64-setup.exe` | 同一 NSIS 安装器 |

使用 Tauri v2 的 `createUpdaterArtifacts: true`，由官方 CLI 生成更新包和 `.sig`。macOS 更新包是应用归档，DMG 用于首次安装；Windows 使用 NSIS 安装器。更新器下载后使用应用内公钥验证签名，验签失败不得安装。

预发布同样生成签名包，但发布为 prerelease 且 `latest=false`，默认正式更新源不会指向预发布。版本按 SemVer 比较，发布标签为 `vX.Y.Z`、`vX.Y.Z-beta.N` 或 `vX.Y.Z-rc.N`。

## 签名配置

现有 Sparkle secret 不用于 Tauri。维护者需要在获得凭据操作授权后，为 Tauri 创建独立密钥，并将其安全备份；此重构不生成、不导出、不轮换发行私钥。

官方 CLI 命令为 `pnpm exec tauri signer generate --write-keys <仓库外路径>`。只在可信环境交互执行，不把私钥或密码写入命令参数、日志、聊天和仓库。详细格式见 [Tauri 更新器文档](https://v2.tauri.app/plugin/updater/)。

GitHub Actions 配置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Repository variable | `TAURI_UPDATER_PUBLIC_KEY` | Tauri 生成的完整公钥内容 |
| Repository secret | `TAURI_SIGNING_PRIVATE_KEY` | 私钥内容 |
| Repository secret | `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | 私钥密码；无密码时为空 |

`scripts/build.mjs` 把公钥和发布版本写入临时 Tauri 配置，构建后清理；私钥仅由官方 CLI 从环境读取，不写入该配置。带 `RELEASE_TAG` 的发行构建缺少公钥或私钥时直接失败。普通本地构建无需密钥，不生成签名更新包；未配置公钥时应用提供发布页入口。

更新签名与 Apple Developer ID 签名 / 公证、Windows Authenticode 签名不同。macOS 默认由 Tauri 对完整应用包执行 ad-hoc 签名，构建入口通过 `codesign --verify --deep --strict` 核验后才复制到 `dist/`。当前流水线未配置平台证书，不声称通过平台公证。不要复用或替换旧 Sparkle 密钥来绕过新配置。

## 构建和发布流程

本地统一入口为 `bash scripts/build.sh`，PowerShell 使用 `node scripts/build.mjs`。可指定 `--target aarch64-apple-darwin`、`--target x86_64-apple-darwin` 或 `--target x86_64-pc-windows-msvc`；Mac 目标在 macOS 构建，Windows 目标在 Windows 构建。所有安装包由锁文件固定版本的 Tauri CLI 打包，不另拼签名或导出流程。

推送版本标签后，Release workflow：

1. 在三个平台目标上安装锁定依赖、检查前端与 Rust 编译；Intel Mac 额外执行保留的 Swift 检查。
2. 注入同一公钥与标签版本，运行统一构建脚本，通过 Tauri CLI 生成安装包和签名。每个平台先上传为 workflow artifact。
3. 全部构建成功后生成 GitHub 原生 Release Notes，按最近正式版本累计 PR；`prepare-release.mjs` 检查三套产物、版本与签名附件完整，生成 `latest.json` 和 `SHA256SUMS.txt`。
4. 安装包、签名、完整清单和校验值上传 draft Release，全部成功后才公开。预发布不替换 latest。

打包前 `collect-licenses.mjs` 从已安装 pnpm 依赖及 Cargo metadata 生成 `Resources/ThirdPartyNotices/dependencies-LICENSES.txt`，随包保留上游许可。不要手工修改该生成文件。

提交、推送和版本标签仍需要用户授权；修改工作流不代表已发布。流水线检查签名附件完整，真实下载验签与安装行为需要下述验收，不能把构建成功当作升级成功。

## 验收边界

首次接入新更新器需要在隔离的临时安装中，用版本递增且公钥相同的两个包完成一次真实升级，覆盖用户确认、下载、验签、安装、重启和设置 / 历史延续。macOS 与 Windows 分别验收，不替换用户正在使用的 `/Applications` 安装或 Windows 安装目录。

使用单独的数据目录和关闭监测的验收配置，避免访问真实登录态；不要以旧 Swift 检查或旧 Sparkle 升级记录代替 Tauri 验收。当前文档记录流程，未宣称已在 Windows 实机或真实签名发布源完成新更新器升级验收。
