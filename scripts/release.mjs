#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { createInterface } from 'node:readline/promises'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'

process.chdir(fileURLToPath(new URL('..', import.meta.url)))
const { values, positionals } = parseArgs({ allowPositionals: true, options: { help: { type: 'boolean' } } })
if (values.help || positionals.length !== 1) {
  console.log('用法：pnpm release <X.Y.Z[-beta.N|-rc.N]>\n准备版本和 CHANGELOG，通过检查并确认后提交、打标签、推送；不等待 CI。')
  process.exit(values.help ? 0 : 1)
}

function run(command, args, capture = false) {
  // Windows 的 pnpm.cmd 需要命令解释器；此处 pnpm 参数仅为固定的 build。
  const result = spawnSync(command, args, { encoding: 'utf8', stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit', shell: process.platform === 'win32' && command === 'pnpm' })
  if (result.error) throw result.error
  if (result.status !== 0) throw new Error(`${command} 执行失败（退出码 ${result.status}）。`)
  return result.stdout?.trim() ?? ''
}

function versionParts(version) {
  const match = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(beta|rc)\.(0|[1-9]\d*))?$/.exec(version)
  if (!match) throw new Error('版本必须为 X.Y.Z、X.Y.Z-beta.N 或 X.Y.Z-rc.N。')
  return [BigInt(match[1]), BigInt(match[2]), BigInt(match[3]), match[4] === 'beta' ? 0n : match[4] === 'rc' ? 1n : 2n, BigInt(match[5] ?? 0)]
}

function requireNewer(parts, previous) {
  const previousParts = versionParts(previous)
  const index = parts.findIndex((part, index) => part !== previousParts[index])
  if (index === -1 || parts[index] < previousParts[index]) throw new Error(`发布版本必须高于 ${previous}。`)
}

function checkRepository(tag) {
  if (run('git', ['branch', '--show-current'], true) !== 'main') throw new Error('请在 main 分支运行发布命令。')
  if (run('git', ['status', '--porcelain'], true)) throw new Error('工作区存在未提交或未跟踪文件，请先处理后再发布。')
  run('git', ['fetch', 'origin', 'main', '--tags'])
  const head = run('git', ['rev-parse', 'HEAD'], true)
  if (head !== run('git', ['rev-parse', 'origin/main'], true)) throw new Error('本地 main 与 origin/main 不一致，请先同步。')
  if (run('git', ['tag', '--list', tag], true)) throw new Error(`标签 ${tag} 已存在。`)
  return head
}

async function main() {
  const version = positionals[0]
  const parts = versionParts(version)
  const manifest = JSON.parse(readFileSync('package.json', 'utf8'))
  requireNewer(parts, manifest.version)
  if (!process.stdin.isTTY) throw new Error('请在交互终端运行 pnpm release，以便审阅并确认发布。')
  const tag = `v${version}`
  const head = checkRepository(tag)
  const repository = run('gh', ['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'], true)
  const previousTag = run('gh', ['release', 'view', '--repo', repository, '--json', 'tagName', '--jq', '.tagName'], true)
  requireNewer(parts, previousTag.slice(1))
  const notes = run('gh', ['api', '--method', 'POST', `repos/${repository}/releases/generate-notes`, '-f', `tag_name=${tag}`, '-f', `target_commitish=${head}`, '-f', `previous_tag_name=${previousTag}`, '--jq', '.body'], true)
  if (!notes) throw new Error('GitHub 未返回版本变更说明。')
  const changelog = readFileSync('CHANGELOG.md', 'utf8')
  const firstVersion = changelog.search(/^## \[/m)
  if (firstVersion === -1) throw new Error('CHANGELOG.md 缺少版本标题。')
  if (changelog.includes(`\n## [${version}](`)) throw new Error(`CHANGELOG.md 已包含 ${version}。`)
  const cargo = readFileSync('src-tauri/Cargo.toml', 'utf8')
  const cargoVersion = /^version = "[^"]+"$/m
  if (!cargoVersion.test(cargo)) throw new Error('Cargo.toml 缺少 package version。')

  manifest.version = version
  writeFileSync('package.json', JSON.stringify(manifest, null, 2) + '\n')
  writeFileSync('src-tauri/Cargo.toml', cargo.replace(cargoVersion, `version = "${version}"`))
  // 版本使用二级标题，GitHub 生成内容的标题降一级，保留完整的变更说明。
  const section = `## [${version}](https://github.com/${repository}/releases/tag/${tag})\n\n${notes.replace(/^(#{1,5}) /gm, '#$1 ')}\n\n`
  writeFileSync('CHANGELOG.md', changelog.slice(0, firstVersion) + section + changelog.slice(firstVersion))
  run('cargo', ['tree', '--offline', '--depth', '0', '--manifest-path', 'src-tauri/Cargo.toml'])
  run('pnpm', ['build'])
  run('cargo', ['check', '--locked', '--manifest-path', 'src-tauri/Cargo.toml'])
  run('git', ['diff', '--check'])
  const files = ['package.json', 'src-tauri/Cargo.toml', 'src-tauri/Cargo.lock', 'CHANGELOG.md']
  run('git', ['--no-pager', 'diff', '--', ...files])
  const terminal = createInterface({ input: process.stdin, output: process.stdout })
  const answer = await terminal.question(`确认提交并推送 ${tag}，触发版本发布？[y/N] `)
  terminal.close()
  if (answer.trim().toLowerCase() !== 'y') {
    console.log('已保留版本与日志改动，未提交、打标签或推送。')
    return
  }
  run('git', ['add', '--', ...files])
  run('git', ['commit', '-m', `chore(release): 准备 ${tag}`, '-m', `- 统一应用与 Cargo 版本为 ${version}。\n- 汇总最近正式版以来的变更，供安装包与更新清单共用。`])
  run('git', ['tag', '-a', tag, '-m', tag])
  run('git', ['push', '--atomic', 'origin', 'main', `refs/tags/${tag}`])
  console.log(`已推送 ${tag}，发布流水线将自动打包；不等待构建结果。`)
}

await main()
