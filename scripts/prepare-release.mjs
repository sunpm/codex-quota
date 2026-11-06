#!/usr/bin/env node
import { createHash } from 'node:crypto'
import { createReadStream, readFileSync, statSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const tag = process.env.RELEASE_TAG
const repository = process.env.GH_REPO
if (!/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$/.test(tag ?? '')) throw new Error('无效的 RELEASE_TAG。')
if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository ?? '')) throw new Error('GH_REPO 必须是 owner/repository。')
const notes = readFileSync('dist/release-changes.md', 'utf8').trim()
if (!notes) throw new Error('缺少当前版本更新说明。')
const platforms = {}
const assets = []
for (const platform of ['darwin-aarch64', 'darwin-x86_64', 'windows-x86_64']) {
  const entry = JSON.parse(readFileSync(`dist/release-assets-${platform}.json`, 'utf8'))
  if (entry.platform !== platform || entry.version !== tag.slice(1) || !entry.update) throw new Error(`${platform} 的版本或签名产物不完整。`)
  if (!entry.assets.includes(entry.update) || !entry.assets.includes(`${entry.update}.sig`)) throw new Error(`${platform} 缺少更新包或签名。`)
  for (const asset of entry.assets) {
    if (!/^CodexQuota-[A-Za-z0-9.-]+$/.test(asset) || !statSync(join('dist', asset)).isFile() || statSync(join('dist', asset)).size === 0) throw new Error(`${platform} 的发布附件无效。`)
  }
  const signature = readFileSync(join('dist', `${entry.update}.sig`), 'utf8').trim()
  if (!signature) throw new Error(`${platform} 的签名为空。`)
  platforms[platform] = { url: `https://github.com/${repository}/releases/download/${tag}/${entry.update}`, signature }
  assets.push(...entry.assets)
}
writeFileSync('dist/latest.json', JSON.stringify({ version: tag.slice(1), notes, pub_date: new Date().toISOString(), platforms }, null, 2) + '\n')
assets.push('latest.json')
const sums = []
for (const asset of assets.sort()) {
  const hash = createHash('sha256')
  for await (const data of createReadStream(join('dist', asset))) hash.update(data)
  sums.push(`${hash.digest('hex')}  ${asset}`)
}
writeFileSync('dist/SHA256SUMS.txt', sums.join('\n') + '\n')
writeFileSync('dist/release-notes.md', `适用于 macOS 13+（Apple Silicon / Intel）与 Windows 10 / 11 x64。Windows 需要 Microsoft Edge WebView2 Runtime，安装器可引导安装。\n\n从旧 Swift / Sparkle 版升级：退出旧应用，手动安装一次本版本。设置与用量历史保留；后续版本使用 Tauri 应用内更新。旧版 appcast 不用于安装 Tauri 更新包。\n\n安装包的更新签名不等同于 Apple 公证或 Windows 代码签名。当前发行配置未提供这些平台证书，系统首次运行时可能要求确认来源。\n\n${notes}\n`)
console.log(`已准备 ${assets.length} 个发布附件及 SHA256SUMS.txt。`)
