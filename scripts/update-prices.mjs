#!/usr/bin/env node
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const date = new Date().toISOString().slice(0, 10)
const result = spawnSync('cargo', ['run', '--locked', '--manifest-path', 'src-tauri/Cargo.toml', '--example', 'update-prices', '--', date, 'crates/quota-core/src/official-pricing.json'], { cwd: fileURLToPath(new URL('..', import.meta.url)), stdio: 'inherit' })
if (result.error) throw result.error
if (result.status !== 0) process.exitCode = result.status ?? 1
else console.log(`官方价格快照已更新（${date}），请同步 BUNDLED_PRICE_DATE 并审查价格 diff。`)
