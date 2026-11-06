<script setup lang="ts">
import { computed, ref } from 'vue'
import type { AppSnapshot, UsageRecord } from '@/types'
import { billingTier, billingTierLabel, costLabel, costTooltip, dateText, exactMoney, money, shortTokens, summarize, summaryMoney } from '@/lib/usage'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'

const props = defineProps<{ title: string; records: UsageRecord[]; state: AppSnapshot }>()
const emit = defineEmits<{ close: [] }>()
const limit = ref(150)
const total = computed(() => summarize(props.records))
const sessions = computed(() => [...new Set(props.records.map(record => record.session))])
const directories = computed(() => [...new Set(props.records.map(record => record.project))].filter(Boolean).sort().map(directory => ({ directory, root: props.state.usage.projectRoots[directory] ?? directory })))
const tiers = computed(() => {
  const groups = new Map<string, UsageRecord[]>()
  for (const record of props.records) {
    const tier = billingTier(record), items = groups.get(tier) ?? []
    items.push(record); groups.set(tier, items)
  }
  return ['Standard', 'Fast', 'Ultrafast', '未知档位'].filter(tier => groups.has(tier)).map(tier => ({ tier, total: summarize(groups.get(tier)!) }))
})
interface Column {
  id: string; label: string; width: number; min: number; numeric?: boolean; optional?: boolean
  value: (record: UsageRecord) => string; title?: (record: UsageRecord) => string
}
const columns = computed<Column[]>(() => [
  { id: 'time', label: '时间', width: 120, min: 100, value: (r: UsageRecord) => dateText(r.date), title: (r: UsageRecord) => dateText(r.date, true) },
  { id: 'model', label: '模型', width: 150, min: 100, value: (r: UsageRecord) => r.model },
  { id: 'input', label: '新增输入', width: 90, min: 75, numeric: true, value: (r: UsageRecord) => shortTokens(r.tokens.input), title: (r: UsageRecord) => r.tokens.input.toLocaleString() },
  { id: 'output', label: '输出', width: 80, min: 64, numeric: true, value: (r: UsageRecord) => shortTokens(r.tokens.output), title: (r: UsageRecord) => r.tokens.output.toLocaleString() },
  { id: 'cached', label: '缓存命中', width: 90, min: 75, numeric: true, value: (r: UsageRecord) => shortTokens(r.tokens.cached), title: (r: UsageRecord) => r.tokens.cached.toLocaleString() },
  { id: 'cacheWrite', label: '缓存写入', width: 90, min: 75, numeric: true, optional: true, value: (r: UsageRecord) => (r.tokens.cacheWriteReported || r.tokens.cacheWrite > 0) ? shortTokens(r.tokens.cacheWrite) : '—', title: (r: UsageRecord) => (r.tokens.cacheWriteReported || r.tokens.cacheWrite > 0) ? r.tokens.cacheWrite.toLocaleString() : '日志未报告' },
  { id: 'cost', label: costLabel(total.value), width: 105, min: 100, numeric: true, value: (r: UsageRecord) => money(r.cost), title: (r: UsageRecord) => exactMoney(r.cost) },
  { id: 'speed', label: '速度', width: 100, min: 85, numeric: true, optional: true, value: (r: UsageRecord) => r.tokens.output >= 200 && (r.estimatedDuration ?? 0) >= 1 ? `≈${(r.tokens.output / r.estimatedDuration!).toFixed(1)} t/s` : '—' },
  { id: 'firstToken', label: '首字', width: 80, min: 64, numeric: true, optional: true, value: (r: UsageRecord) => r.estimatedFirstToken != null ? `≈${r.estimatedFirstToken.toFixed(2)}s` : '—' },
  { id: 'billingTier', label: '计费档位', width: 150, min: 100, optional: true, value: (r: UsageRecord) => billingTierLabel(r) },
].filter(column => !column.optional || props.state.settings.detailColumns.includes(column.id)))
const widths = ref<Record<string, number>>({})
const tableWidth = computed(() => columns.value.reduce((sum, column) => sum + (widths.value[column.id] ?? column.width), 0))
function resizeColumn(event: PointerEvent, column: Column) {
  if (event.button !== 0) return
  const handle = event.currentTarget as HTMLElement
  const row = handle.parentElement!.parentElement!
  Array.from(row.children).forEach((cell, index) => { widths.value[columns.value[index]!.id] = cell.getBoundingClientRect().width })
  const start = event.clientX, width = widths.value[column.id]!
  handle.setPointerCapture(event.pointerId)
  const move = (next: PointerEvent) => { widths.value[column.id] = Math.max(column.min, width + next.clientX - start) }
  const stop = () => { handle.removeEventListener('pointermove', move); handle.removeEventListener('lostpointercapture', stop) }
  handle.addEventListener('pointermove', move); handle.addEventListener('lostpointercapture', stop)
}
function stepColumn(event: KeyboardEvent, column: Column, amount: number) {
  const width = (event.currentTarget as HTMLElement).parentElement!.getBoundingClientRect().width
  widths.value[column.id] = Math.max(column.min, width + amount)
}
</script>
<template>
  <Dialog :open="true" @update:open="value => { if (!value) emit('close') }"><DialogContent class="detail-dialog"><DialogHeader><DialogTitle>{{ title }}</DialogTitle><DialogDescription>{{ records.length }} 条用量记录 · 当前筛选范围</DialogDescription></DialogHeader>
    <div class="detail-context">
      <div class="detail-totals"><strong :title="total.tokens.toLocaleString()">{{ shortTokens(total.tokens) }} Tokens</strong><span>{{ costLabel(total) }} <strong :title="costTooltip(total)">{{ summaryMoney(total) }}</strong></span></div>
      <div v-if="sessions.length === 1" class="session-identity"><span class="muted">会话 ID</span><code>{{ sessions[0] }}</code></div>
      <details v-else><summary>会话 ID（{{ sessions.length }}）</summary><code v-for="session in sessions" :key="session" class="session-id">{{ session }}</code></details>
      <details v-if="directories.length"><summary>工作目录</summary><div v-for="{ directory, root } in directories" :key="directory" class="directory"><code>{{ directory }}</code><div v-if="root !== directory" class="muted">主项目：<code>{{ root }}</code></div></div></details>
      <div v-if="tiers.length > 1" class="tier-summary"><div v-for="item in tiers" :key="item.tier"><h3>{{ item.tier }}</h3><span :title="item.total.tokens.toLocaleString()">{{ shortTokens(item.total.tokens) }} Tokens</span><span class="muted" :title="costTooltip(item.total)">{{ costLabel(item.total) }} {{ summaryMoney(item.total) }}</span></div></div>
    </div>
    <div class="table-scroll"><table class="detail-table" :style="{ width: `${tableWidth}px` }"><colgroup><col v-for="column in columns" :key="column.id" :style="{ width: `${widths[column.id] ?? column.width}px` }" /></colgroup><thead><tr><th v-for="column in columns" :key="column.id" :class="{ number: column.numeric }">{{ column.label }}<span class="column-resize" role="separator" tabindex="0" aria-orientation="vertical" :aria-label="`调整${column.label}列宽`" :aria-valuenow="Math.round(widths[column.id] ?? column.width)" :aria-valuemin="column.min" @pointerdown.prevent="resizeColumn($event, column)" @keydown.left.prevent="stepColumn($event, column, -10)" @keydown.right.prevent="stepColumn($event, column, 10)" /></th></tr></thead><tbody><tr v-for="record in records.slice(0, limit)" :key="record.id"><td v-for="column in columns" :key="column.id" :class="{ number: column.numeric, 'model-cell': column.id === 'model' }" :title="column.title ? column.title(record) : column.value(record)">{{ column.value(record) }}</td></tr></tbody></table><Button v-if="records.length > limit" class="load-more" variant="outline" size="sm" @click="limit += 150">显示更多</Button></div>
    <div class="dialog-actions"><Button @click="emit('close')">完成</Button></div>
  </DialogContent></Dialog>
</template>
<style scoped>
.detail-context { display: grid; gap: 12px; font-size: 12px; max-height: 32vh; overflow: auto; flex-shrink: 0; }
.detail-totals, .session-identity { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px 16px; font-variant-numeric: tabular-nums; }
.detail-context code { user-select: text; overflow-wrap: anywhere; }
.detail-context summary { cursor: pointer; width: fit-content; }
.detail-context summary:focus-visible { outline: 2px solid var(--primary); outline-offset: 3px; }
.session-id { display: block; margin-top: 6px; }
.directory { display: grid; gap: 4px; margin-top: 8px; }
.tier-summary { display: flex; flex-wrap: wrap; gap: 12px 28px; padding-top: 12px; border-top: 1px solid var(--border); font-variant-numeric: tabular-nums; }
.tier-summary > div { display: grid; gap: 4px; }
.detail-table { table-layout: fixed; min-width: 100%; font-variant-numeric: tabular-nums; }
.detail-table td { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.column-resize { position: absolute; top: 0; bottom: 0; right: 0; width: 6px; cursor: col-resize; touch-action: none; }
.column-resize:hover, .column-resize:focus-visible { background: var(--primary); }
</style>
