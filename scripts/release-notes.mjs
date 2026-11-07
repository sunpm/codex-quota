#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

process.chdir(fileURLToPath(new URL('..', import.meta.url)))
const version = JSON.parse(readFileSync('package.json', 'utf8')).version
if (process.env.RELEASE_TAG !== `v${version}`) throw new Error('发布标签必须与 package.json 的版本一致。')
const changelog = readFileSync('CHANGELOG.md', 'utf8')
const sections = [...changelog.matchAll(/^## \[([^\]]+)\]\([^\n]+\).*$/gm)]
const index = sections.findIndex(section => section[1] === version)
if (index === -1) throw new Error(`CHANGELOG.md 缺少 ${version} 的变更说明。`)
const section = sections[index]
const notes = changelog.slice(section.index + section[0].length, sections[index + 1]?.index).trim()
if (!notes) throw new Error(`${version} 的变更说明不能为空。`)
mkdirSync('work', { recursive: true })
writeFileSync('work/release-changes.md', notes + '\n')
console.log(`已提取 ${version} 的变更说明。`)
