#!/usr/bin/env node
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
process.chdir(root)
const { values } = parseArgs({ options: { target: { type: 'string' }, bundles: { type: 'string' } } })
const host = spawnSync('rustc', ['-vV'], { encoding: 'utf8' })
if (host.status !== 0) throw new Error('无法运行 rustc，请安装 Rust stable。')
const target = values.target ?? host.stdout.match(/^host: (.+)$/m)?.[1]
const platforms = {
  'aarch64-apple-darwin': { os: 'darwin', name: 'macOS-AppleSilicon', update: 'darwin-aarch64', bundles: 'app,dmg' },
  'x86_64-apple-darwin': { os: 'darwin', name: 'macOS-Intel', update: 'darwin-x86_64', bundles: 'app,dmg' },
  'x86_64-pc-windows-msvc': { os: 'win32', name: 'Windows-x64', update: 'windows-x86_64', bundles: 'nsis' },
}
const platform = platforms[target]
if (!platform || platform.os !== process.platform) throw new Error('请在 macOS 构建 Mac 包，在 Windows 构建 Windows x64 包。')
const bundles = (values.bundles ?? platform.bundles).split(',')
if (bundles.some(bundle => !platform.bundles.split(',').includes(bundle))) throw new Error('当前平台不支持指定的安装包格式。')
const tag = process.env.RELEASE_TAG || undefined
if (tag && !/^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$/.test(tag)) {
  throw new Error('RELEASE_TAG 必须是 vX.Y.Z 或带 beta / rc 后缀的版本标签。')
}
const version = tag?.slice(1) ?? JSON.parse(readFileSync('package.json', 'utf8')).version
const publicKey = process.env.TAURI_UPDATER_PUBLIC_KEY?.trim()
const signing = Boolean(process.env.TAURI_SIGNING_PRIVATE_KEY)
if (tag && (!publicKey || !signing)) throw new Error('发布构建必须配置 TAURI_UPDATER_PUBLIC_KEY 和 TAURI_SIGNING_PRIVATE_KEY。')
if (signing && !publicKey) throw new Error('签名构建必须同时配置对应的 TAURI_UPDATER_PUBLIC_KEY。')
const config = {
  version,
  bundle: { createUpdaterArtifacts: signing },
  ...(publicKey ? { plugins: { updater: { pubkey: publicKey } } } : {}),
}
mkdirSync('work', { recursive: true })
const temporary = mkdtempSync(join(root, 'work', 'tauri-build-'))
process.on('exit', () => rmSync(temporary, { recursive: true, force: true }))
const configPath = join(temporary, 'config.json')
writeFileSync(configPath, JSON.stringify(config))
const notices = spawnSync(process.execPath, ['scripts/collect-licenses.mjs'], { stdio: 'inherit' })
if (notices.status !== 0) process.exit(notices.status ?? 1)
const result = spawnSync(process.execPath, [
  'node_modules/@tauri-apps/cli/tauri.js', 'build', '--target', target,
  '--bundles', bundles.join(','), '--config', configPath, '--', '--locked',
], { stdio: 'inherit' })
if (result.status !== 0) process.exit(result.status ?? 1)

const bundleRoot = join(root, 'src-tauri', 'target', target, 'release', 'bundle')
const dist = join(root, 'dist')
mkdirSync(dist, { recursive: true })
const assets = []
let update
if (platform.os === 'darwin') {
  const app = join(bundleRoot, 'macos', 'Codex Quota.app')
  const signature = spawnSync('codesign', ['--verify', '--deep', '--strict', app], { stdio: 'inherit' })
  if (signature.status !== 0) process.exit(signature.status ?? 1)
  const appDestination = join(dist, platform.name, 'Codex Quota.app')
  mkdirSync(dirname(appDestination), { recursive: true })
  rmSync(appDestination, { recursive: true, force: true })
  cpSync(app, appDestination, { recursive: true, verbatimSymlinks: true })
  console.log(appDestination)
  if (bundles.includes('dmg')) {
    const dmg = readdirSync(join(bundleRoot, 'dmg')).find(name => name.includes(`_${version}_`) && name.endsWith('.dmg'))
    if (!dmg) throw new Error('Tauri 没有生成 DMG。')
    const name = `CodexQuota-${platform.name}.dmg`
    cpSync(join(bundleRoot, 'dmg', dmg), join(dist, name))
    assets.push(name)
  }
  if (signing) {
    const name = `CodexQuota-${platform.name}.app.tar.gz`
    cpSync(`${app}.tar.gz`, join(dist, name))
    cpSync(`${app}.tar.gz.sig`, join(dist, `${name}.sig`))
    assets.push(name, `${name}.sig`)
    update = name
  }
} else {
  const installer = readdirSync(join(bundleRoot, 'nsis')).find(name => name.includes(`_${version}_`) && name.endsWith('-setup.exe'))
  if (!installer) throw new Error('Tauri 没有生成 NSIS 安装包。')
  const name = 'CodexQuota-Windows-x64-setup.exe'
  cpSync(join(bundleRoot, 'nsis', installer), join(dist, name))
  assets.push(name)
  if (signing) {
    cpSync(join(bundleRoot, 'nsis', `${installer}.sig`), join(dist, `${name}.sig`))
    assets.push(`${name}.sig`)
    update = name
  }
}
writeFileSync(join(dist, `release-assets-${platform.update}.json`), JSON.stringify({ version, platform: platform.update, assets, update }, null, 2) + '\n')
for (const name of assets) console.log(join(dist, name))
