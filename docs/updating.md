# 打包、更新与发布

跨平台版本使用 Tauri 2 updater，在 macOS 和 Windows 上检查、下载、验签、安装与重启。默认每天检查最新正式版；用户确认安装后才下载与安装，后台检查不自行安装。更新保留原有设置与用量历史。

自动检查与手动检查发现新版本时均弹窗，并展示服务返回的更新说明；长说明可滚动阅读。同一次运行中，同一版本只自动提示一次，关闭后仍可通过手动检查再次打开；若首次打开的版本说明或通知引导尚未关闭，则等其关闭后再提示。已是最新版本或检查失败时，在设置页更新区域显示结果。

本文是当前打包入口、产物和发布流程的维护文档。应用版本以 `package.json` 为准；Release 固定安装提示维护在 [release-notes.md](release-notes.md)，版本变更统一保存在 [CHANGELOG.md](../CHANGELOG.md)。手动发布时由 GitHub 原生 Release Notes 生成变更，CI 直接使用已提交的版本段落。

## 手动发布

普通 PR 合并只触发 `Check` 编译检查，可以持续累计改动。准备发版时，由维护者在本机显式运行：

```sh
pnpm release 0.25.3
```

支持 `X.Y.Z`、`X.Y.Z-beta.N` 和 `X.Y.Z-rc.N`；用 `pnpm release --help` 查看用法。需要已安装锁定依赖、Node.js、pnpm、Rust、Git 和已登录的 GitHub CLI（`gh`），并具备仓库推送权限。命令要求当前为 `main`、工作区干净（包括未跟踪文件），拉取远端引用后本地提交与 `origin/main` 一致，目标版本高于源码版本及最近正式版，且标签未被使用。脚本不自动合并分支。

`scripts/release.mjs` 按顺序执行：

1. 从最近成功发布的正式版到当前远端提交，通过 GitHub 原生 API 生成一次变更说明，插入 CHANGELOG 顶部；旧版本保持原样。预发布同样从最近正式版累计。
2. 更新 `package.json` 和 `src-tauri/Cargo.toml`，通过 `cargo tree --offline` 更新 `Cargo.lock`。Tauri 配置引用 `../package.json`，网页预览直接导入该版本，不另存版本号。
3. 运行 `pnpm build`、`cargo check --locked` 和 `git diff --check`，展示版本、锁文件与日志差异。
4. 在终端确认后，提交这四个文件、创建对应标签，并用一次 `git push --atomic` 推送 `main` 与该标签。标签推送触发下面的 CI 发布；脚本随后结束，不等待构建。

确认前不会提交、创建标签或推送。取消或检查失败时，保留本地改动供审阅，不自动回滚；再次运行需先将本次准备的改动处理干净。推送失败时保留本地提交和标签，排除原因后可重试同一条 `git push --atomic origin main refs/tags/<版本标签>`；不重复创建标签，也不强制覆盖远端。若仓库要求所有变更经 PR 合并，可将准备好的四个文件走 PR，再在合并提交上手动打同版本标签。

首次接入已将源码版本对齐现有 `v0.25.2` 标签，并按 GitHub 原生生成结果补齐 `0.25.1`、`0.25.2` 日志；没有重写既有标签。旧版本的人工整理条目保留。

流程参考 [Vue 3 手动发布脚本](https://github.com/vuejs/core/blob/main/scripts/release.js)，使用 Node.js 标准库和仓库现有工具自行实现，未复制外部代码或增加依赖。版本来源依据 [Tauri version 配置](https://v2.tauri.app/reference/config/#version)，并核对了上游关于多处版本同步的 [issue #15264](https://github.com/tauri-apps/tauri/issues/15264)。

## 本地打包

需要 Node.js 22.12+、满足 `package.json` 中 `engines.pnpm` 范围的 pnpm、Rust stable（至少 1.90），以及 [Tauri 平台依赖](https://v2.tauri.app/start/prerequisites/)。macOS 安装 Xcode Command Line Tools；Windows 安装 Visual Studio C++ Build Tools 与 Windows SDK。CI 从该字段读取 pnpm 版本范围，依赖仍通过锁文件和 `--frozen-lockfile` 固定。

在仓库根目录安装锁定依赖后，构建当前平台：

```sh
pnpm install --frozen-lockfile
node scripts/build.mjs
```

`scripts/build.mjs` 是 macOS、Windows 的共同实现，可在 PowerShell 或终端执行。`bash scripts/build.sh` 是同一实现的兼容入口；`scripts/package-dmg.sh arm64|x86_64` 只负责转换 Mac 架构参数。

| 构建目标 | 执行环境 | 命令 | 安装包（位于 `dist/`） |
| --- | --- | --- | --- |
| macOS Apple Silicon | macOS | `node scripts/build.mjs --target aarch64-apple-darwin` | `CodexQuota-macOS-AppleSilicon.dmg` |
| macOS Intel | macOS | `node scripts/build.mjs --target x86_64-apple-darwin` | `CodexQuota-macOS-Intel.dmg` |
| Windows x64 | Windows | `node scripts/build.mjs --target x86_64-pc-windows-msvc` | `CodexQuota-Windows-x64-setup.exe` |

Mac 双架构构建前用 `rustup target add aarch64-apple-darwin x86_64-apple-darwin` 安装两个目标，再依次执行上表的 Mac 命令。Windows 使用原生 Windows 环境或下述 GitHub Actions runner，不在 Mac 上另建交叉编译流程。

默认 Mac 生成 `.app` 和 DMG，Windows 生成 NSIS 安装器。只检查 Mac 应用包时可加 `--bundles app`。Mac 应用副本在 `dist/macOS-AppleSilicon/Codex Quota.app` 或 `dist/macOS-Intel/Codex Quota.app`；打包不替换 `/Applications` 中的安装。构建前退出正在使用的对应 `dist/` 副本。

构建顺序为：生成依赖许可 → Tauri `beforeBuildCommand` 执行一次 `pnpm build` → Cargo 使用 `--locked` 编译 → Tauri 打包 → 核验并复制产物。前端和 Rust 编译失败都会终止打包，不需要先手动再构建一次前端。依赖许可由 `collect-licenses.mjs` 从已安装 pnpm 依赖和 Cargo metadata 生成，写入随包的 `Resources/ThirdPartyNotices/dependencies-LICENSES.txt`；不要手工修改。

普通本地构建无需更新签名密钥，不生成 `.sig` 或签名更新归档。构建始终使用 `package.json` 的版本号，并校验 Cargo 版本一致。`RELEASE_TAG` 非空时必须等于 `v` 加源码版本，同时提供更新签名密钥及 `CODEX_QUOTA_RELEASE_NOTES_FILE` 指向的本版本 Markdown 变更说明；不再以标签静默覆盖源码版本。`release-assets-<平台>.json` 是构建脚本输出给汇总步骤的内部清单，不是用户安装包。

本地可选设置 `CODEX_QUOTA_RELEASE_NOTES_FILE`（相对于构建命令的工作目录或绝对路径），构建脚本会将 UTF-8 Markdown 嵌入安装包。该版本首次打开时展示，关闭后沿用 `updates.lastShownReleaseNotesVersion` 记录已读；未提供说明时不弹窗。说明使用标题、列表、代码、链接与 `details` / `summary` 折叠排版；HTML 注释正常隐藏，代码示例中的注释保持原文。Markdown 渲染后统一清理 HTML，仅保留排版标签与必要属性，不加载图片或执行脚本，链接沿用应用的外部来源限制。此文件应为对应版本的实际变更，不使用 `docs/release-notes.md` 中的通用安装提示代替。

## CI 打包与发布

现有 `Release` workflow 共用三平台矩阵：Apple Silicon Mac、Intel Mac、Windows x64，均调用 `node scripts/build.mjs --target <目标>`。前端检查与 Rust 编译由统一构建入口完成，不再编译旧 Swift 应用或执行其测试。

| 入口 | 结果 |
| --- | --- |
| 普通 PR 合并 / 分支推送 | 仅运行 `Check` 编译检查，不发版 |
| Actions → Release → Run workflow | 打包所选分支或标签，安装包保存在 `release-<target>` artifacts 中，保留 7 天；不生成更新签名，不创建或发布 Release |
| `pnpm release <版本>` 确认后推送版本标签 | 校验版本与 CHANGELOG，使用更新签名密钥生成三平台安装包和更新包，全部成功后汇总并发布 |

手动入口需要工作流文件已进入仓库默认分支，待构建代码也需先提交、推送到所选分支。已有运行记录的工作流也可通过 `gh workflow run release.yml --ref <分支>` 指定分支，详见 [GitHub 手动运行说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)。它使用源码中的版本号，适合验证 macOS / Windows 安装包；下载 workflow artifact 后解压即可取得对应安装器。

标签发布依次执行：

1. `release-notes.mjs` 校验标签等于源码版本，从 CHANGELOG 提取该版本段落并保存为 artifact；缺少对应段落或内容为空时停止。不在 CI 重新生成说明。
2. 三平台安装锁定依赖，下载同一份说明，注入公钥及说明路径，校验标签与源码版本一致后运行统一构建入口；安装产物上传为 workflow artifact。
3. `prepare-release.mjs` 检查三套产物、版本与签名附件，生成 `latest.json` 和 `SHA256SUMS.txt`；读取 `docs/release-notes.md` 并附上本次变更，生成 `dist/release-notes.md`。应用内更新清单只包含本次变更，不重复安装提示。
4. 安装包、签名、完整清单和校验值上传 draft Release，全部成功后才公开。预发布不替换 latest。

三平台构建从同一 artifact 嵌入版本说明，汇总步骤将同一内容写入 `latest.json`，并与通用安装提示组合为 Release 正文，避免安装后与更新前看到不同说明。

提交、推送和版本标签仍需用户授权。修改或运行只打包工作流不代表已发布；编译和产物检查不能代替安装与真实升级验收。

## 从 Swift / Sparkle 版本迁移

旧版使用 Sparkle XML appcast，新版使用 Tauri 的 JSON 清单与 minisign 更新签名。**需要退出旧版并手动安装一次 Tauri 版本。** 不把 Tauri `.app.tar.gz` 或 Windows 安装器写进旧 Sparkle 清单，也不假定两套密钥可互换。

保留 Bundle ID `local.codexquotadock.app`、`CodexQuotaDock` 数据目录及旧偏好键。首次启动从 macOS 原偏好域导入设置、定价、额度趋势与通知基线，旧偏好域和原始 Codex 登录态不被改写。已采集用量继续使用原历史文件。

历史 Release 中的 Sparkle 包和 appcast 保留；新 Release 不生成 Sparkle appcast。旧客户端因最新 Release 不含旧清单而无法自动更新时，应从发布页手动安装。后续 Tauri 版本通过 `latest.json` 更新。旧版源码、签名配置与 2026-10-29 的实际验收记录见 [Swift / Sparkle 归档](archive/updating-sparkle.md)，不适用于新更新器；当前仓库已移除旧构建与 appcast 工具。

## 更新清单与安装包

正式更新源为 `https://github.com/sunpm/codex-quota/releases/latest/download/latest.json`。清单包含版本、说明、时间，以及三个平台的固定标签下载地址和签名：

| 平台键 | 更新包 | 首次安装 |
| --- | --- | --- |
| `darwin-aarch64` | `CodexQuota-macOS-AppleSilicon.app.tar.gz` | Apple Silicon DMG |
| `darwin-x86_64` | `CodexQuota-macOS-Intel.app.tar.gz` | Intel DMG |
| `windows-x86_64` | `CodexQuota-Windows-x64-setup.exe` | 同一 NSIS 安装器 |

最新正式版仍为旧 Sparkle 发布、尚无 `latest.json` 时，应用回退查询 GitHub 正式版信息：没有更高版本则显示“已是最新版本”；存在更高版本则显示版本与说明，通过发布页手动安装。此路径不启用应用内安装。网络或清单解析失败仍显示错误，不视为已是最新版本。

使用 Tauri v2 的 `createUpdaterArtifacts: true`，由官方 CLI 生成更新包和 `.sig`。macOS 更新包是应用归档，DMG 用于首次安装；Windows 使用 NSIS 安装器。更新器下载后使用应用内公钥验证签名，验签失败不得安装。

预发布同样生成签名包，但发布为 prerelease 且 `latest=false`，默认正式更新源不会指向预发布。版本按 SemVer 比较，发布标签为 `vX.Y.Z`、`vX.Y.Z-beta.N` 或 `vX.Y.Z-rc.N`。

## 签名配置

现有 Sparkle secret 不用于 Tauri。已于 2026-11-06 经维护者授权创建项目独立的 Tauri 签名密钥，并配置下述 GitHub variable 和 secret；旧 Sparkle 配置保留。本机备份位于仓库外的受限目录，后续发布复用同一密钥，不重新生成或替换。

私钥需要另存一份到加密存储；GitHub secret 不能替代维护者自己的备份。重新创建或轮换密钥仍需单独获得凭据操作授权。

官方 CLI 命令为 `pnpm exec tauri signer generate --write-keys <仓库外路径>`。只在可信环境交互执行，不把私钥或密码写入命令参数、日志、聊天和仓库。详细格式见 [Tauri 更新器文档](https://v2.tauri.app/plugin/updater/)。

GitHub Actions 配置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Repository variable | `TAURI_UPDATER_PUBLIC_KEY` | Tauri 生成的完整公钥内容 |
| Repository secret | `TAURI_SIGNING_PRIVATE_KEY` | 私钥内容 |
| Repository secret | `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | 私钥密码；无密码时为空 |

`scripts/build.mjs` 把公钥和更新产物开关写入临时 Tauri 配置，构建后清理；版本由基础 Tauri 配置读取 `package.json`，私钥仅由官方 CLI 从环境读取，不写入该配置。带 `RELEASE_TAG` 的发行构建缺少公钥或私钥时直接失败。普通本地构建无需密钥，不生成签名更新包；未配置公钥时应用提供发布页入口。

更新签名与 Apple Developer ID 签名 / 公证、Windows Authenticode 签名不同。macOS 默认由 Tauri 对完整应用包执行 ad-hoc 签名，构建入口通过 `codesign --verify --deep --strict` 核验后才复制到 `dist/`。当前流水线未配置平台证书，不声称通过平台公证。不要复用或替换旧 Sparkle 密钥来绕过新配置。

## 验证

macOS 或 Windows Git Bash 使用 `bash scripts/test.sh`，它依次运行前端类型检查与构建、Rust 编译检查。Windows PowerShell 的同等编译检查为：

```powershell
pnpm build
cargo check --locked --manifest-path src-tauri/Cargo.toml
```

日常提交 / PR 的 `Check` workflow 编译三平台，不生成安装器；需要验证安装包时使用 `Release` workflow 的手动入口。编译检查不替代运行时行为与升级验收。

### 升级验收边界

首次接入新更新器需要在隔离的临时安装中，用版本递增且公钥相同的两个包完成一次真实升级，覆盖用户确认、下载、验签、安装、重启和设置 / 历史延续。macOS 与 Windows 分别验收，不替换用户正在使用的 `/Applications` 安装或 Windows 安装目录。

使用单独的数据目录和关闭监测的验收配置，避免访问真实登录态；不要以旧 Swift 检查或旧 Sparkle 升级记录代替 Tauri 验收。当前文档记录流程，未宣称已在 Windows 实机或真实签名发布源完成新更新器升级验收。
