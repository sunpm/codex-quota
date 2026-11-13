<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useLocalStorage } from '@vueuse/core'
import { isPlainObject } from '@pmun/utils'
import { ChevronRight } from '@lucide/vue'
import type { AppSnapshot, UsageRecord } from '@/types'
import { basename, billingTierLabel, costLabel, dateText, exactMoney, money, shortTokens, summarize } from '@/lib/usage'
import { compareTableNumbers, useTablePagination, type SortDirection } from '@/lib/table'
import DetailColumnsMenu from './DetailColumnsMenu.vue'
import TablePagination from './TablePagination.vue'
import TableSortButton from './TableSortButton.vue'
import UsageRecordDialog from './UsageRecordDialog.vue'

const props = defineProps<{ records: UsageRecord[]; state: AppSnapshot; showIdentity?: boolean; resetKey?: string }>()
const total = computed(() => summarize(props.records))
const selected = ref<UsageRecord | null>(null)
interface Column {
  id: string; label: string; width: number; min: number; numeric?: boolean; optional?: boolean
  value: (record: UsageRecord) => string; title?: (record: UsageRecord) => string
  sortValue?: (record: UsageRecord) => number | null
}
const allColumns = computed<Column[]>(() => [
  { id: 'time', label: '时间', width: 120, min: 100, sortValue: r => r.date, value: (r: UsageRecord) => dateText(r.date), title: (r: UsageRecord) => dateText(r.date, true) },
  ...(props.showIdentity ? [
    { id: 'session', label: '对话', width: 210, min: 120, value: (r: UsageRecord) => props.state.usage.sessionTitles[r.session] || `${basename(props.state.usage.projectRoots[r.project] ?? r.project)} · ${r.session.slice(0, 12)}`, title: (r: UsageRecord) => `${props.state.usage.sessionTitles[r.session] || r.session}\n${r.session}` },
    { id: 'project', label: '项目', width: 160, min: 100, value: (r: UsageRecord) => basename(props.state.usage.projectRoots[r.project] ?? r.project), title: (r: UsageRecord) => r.project },
  ] : []),
  { id: 'model', label: '模型', width: 200, min: 100, value: (r: UsageRecord) => r.model },
  { id: 'input', label: '新增输入', width: 90, min: 75, numeric: true, sortValue: r => r.tokens.input, value: (r: UsageRecord) => shortTokens(r.tokens.input), title: (r: UsageRecord) => r.tokens.input.toLocaleString() },
  { id: 'output', label: '输出', width: 80, min: 64, numeric: true, sortValue: r => r.tokens.output, value: (r: UsageRecord) => shortTokens(r.tokens.output), title: (r: UsageRecord) => r.tokens.output.toLocaleString() },
  { id: 'cached', label: '缓存命中', width: 90, min: 75, numeric: true, sortValue: r => r.tokens.cached, value: (r: UsageRecord) => shortTokens(r.tokens.cached), title: (r: UsageRecord) => r.tokens.cached.toLocaleString() },
  { id: 'cacheWrite', label: '缓存写入', width: 90, min: 75, numeric: true, optional: true, sortValue: r => (r.tokens.cacheWriteReported || r.tokens.cacheWrite > 0) ? r.tokens.cacheWrite : null, value: (r: UsageRecord) => (r.tokens.cacheWriteReported || r.tokens.cacheWrite > 0) ? shortTokens(r.tokens.cacheWrite) : '—', title: (r: UsageRecord) => (r.tokens.cacheWriteReported || r.tokens.cacheWrite > 0) ? r.tokens.cacheWrite.toLocaleString() : '日志未报告' },
  { id: 'cost', label: costLabel(total.value), width: 105, min: 100, numeric: true, sortValue: r => r.cost === null ? null : Number(r.cost), value: (r: UsageRecord) => money(r.cost), title: (r: UsageRecord) => exactMoney(r.cost) },
  { id: 'speed', label: '速度', width: 100, min: 85, numeric: true, optional: true, sortValue: r => r.tokens.output >= 200 && (r.estimatedDuration ?? 0) >= 1 ? r.tokens.output / r.estimatedDuration! : null, value: (r: UsageRecord) => r.tokens.output >= 200 && (r.estimatedDuration ?? 0) >= 1 ? `≈${(r.tokens.output / r.estimatedDuration!).toFixed(1)} t/s` : '—' },
  { id: 'firstToken', label: '首字', width: 80, min: 64, numeric: true, optional: true, sortValue: r => r.estimatedFirstToken ?? null, value: (r: UsageRecord) => r.estimatedFirstToken != null ? `≈${r.estimatedFirstToken.toFixed(2)}s` : '—' },
  { id: 'billingTier', label: '计费档位', width: 150, min: 100, optional: true, value: (r: UsageRecord) => billingTierLabel(r) },
])
const columns = computed(() => allColumns.value.filter(column => !column.optional || props.state.settings.detailColumns.includes(column.id)))
const widths = useLocalStorage<Record<string, number>>('usage.detail.widths.v1', {}, {
  serializer: {
    read(raw) {
      const saved: unknown = JSON.parse(raw)
      if (!isPlainObject(saved)) return {}
      return Object.fromEntries(allColumns.value.flatMap(column => {
        const width = saved[column.id]
        return typeof width === 'number' && Number.isFinite(width) ? [[column.id, Math.min(800, Math.max(column.min, width))]] : []
      }))
    },
    write: JSON.stringify,
  },
})
const sort = ref('time')
const direction = ref<SortDirection>('desc')
const sortedRecords = computed(() => {
  const column = allColumns.value.find(column => column.id === sort.value)!
  return [...props.records].sort((a, b) => compareTableNumbers(column.sortValue!(a), column.sortValue!(b), direction.value) || a.id.localeCompare(b.id))
})
const { page, pageSize, pageRows } = useTablePagination(sortedRecords, 'usage.detail.pageSize.v1')
const tableScroll = ref<HTMLElement | null>(null)
watch([sort, direction, () => props.resetKey], () => { page.value = 1 })
watch([page, pageSize, sort, direction, () => props.resetKey], () => { tableScroll.value?.scrollTo(0, 0) }, { flush: 'post' })
watch(columns, visible => { if (!visible.some(column => column.id === sort.value)) { sort.value = 'time'; direction.value = 'desc' } })
function selectSort(column: Column) {
  direction.value = sort.value === column.id && direction.value === 'desc' ? 'asc' : 'desc'
  sort.value = column.id
}
const tableWidth = computed(() => columns.value.reduce((sum, column) => sum + (widths.value[column.id] ?? column.width), 0))
function freezeColumnWidths(row: HTMLElement) {
  Array.from(row.children).forEach((cell, index) => { widths.value[columns.value[index]!.id] = cell.getBoundingClientRect().width })
}
function resizeColumn(event: PointerEvent, column: Column) {
  if (event.button !== 0) return
  const handle = event.currentTarget as HTMLElement
  freezeColumnWidths(handle.parentElement!.parentElement!)
  const start = event.clientX, width = widths.value[column.id]!
  handle.setPointerCapture(event.pointerId)
  const move = (next: PointerEvent) => { widths.value[column.id] = Math.min(800, Math.max(column.min, width + next.clientX - start)) }
  const stop = () => { handle.removeEventListener('pointermove', move); handle.removeEventListener('lostpointercapture', stop) }
  handle.addEventListener('pointermove', move); handle.addEventListener('lostpointercapture', stop)
}
function stepColumn(event: KeyboardEvent, column: Column, amount: number) {
  freezeColumnWidths((event.currentTarget as HTMLElement).parentElement!.parentElement!)
  widths.value[column.id] = Math.min(800, Math.max(column.min, widths.value[column.id]! + amount))
}
</script>
<template>
  <div class="record-table-content">
    <div v-if="!showIdentity" class="detail-toolbar"><slot name="toolbar" /><div class="heading-actions"><span class="muted">可选列</span><DetailColumnsMenu :selected="state.settings.detailColumns" /></div></div>
    <div ref="tableScroll" class="table-scroll"><table class="detail-table" :style="{ width: `${tableWidth}px`, minWidth: widths.model === undefined ? '100%' : undefined }"><colgroup><col v-for="column in columns" :key="column.id" :style="{ width: column.id === 'model' && widths.model === undefined ? undefined : `${widths[column.id] ?? column.width}px` }" /></colgroup><thead><tr><th v-for="column in columns" :key="column.id" :class="{ number: column.numeric }" :aria-sort="column.sortValue ? sort === column.id ? direction === 'asc' ? 'ascending' : 'descending' : 'none' : undefined"><TableSortButton v-if="column.sortValue" :label="column.label" :active="sort === column.id" :direction="direction" @click="selectSort(column)" /><template v-else>{{ column.label }}</template><span class="column-resize" role="separator" tabindex="0" aria-orientation="vertical" :aria-label="`调整${column.label}列宽`" :aria-valuenow="Math.round(widths[column.id] ?? column.width)" :aria-valuemin="column.min" :aria-valuemax="800" @pointerdown.prevent="resizeColumn($event, column)" @keydown.left.prevent="stepColumn($event, column, -10)" @keydown.right.prevent="stepColumn($event, column, 10)" /></th></tr></thead><tbody><tr v-for="record in pageRows" :key="record.id"><td v-for="column in columns" :key="column.id" :class="{ number: column.numeric, 'model-cell': column.id === 'model' }" :title="column.title ? column.title(record) : column.value(record)"><button v-if="column.id === 'time'" class="record-link" :aria-label="`查看 ${dateText(record.date, true)} 的用量记录`" @click="selected = record">{{ column.value(record) }}<ChevronRight :size="12" /></button><template v-else>{{ column.value(record) }}</template></td></tr></tbody></table></div>
    <TablePagination v-model:page="page" v-model:page-size="pageSize" :total="records.length" />
    <div v-if="!records.length" class="empty-state">{{ state.usage.scannedAt === null ? '尚未读取本机日志' : '没有匹配的记录' }}</div>
    <UsageRecordDialog v-if="selected" :record="selected" :state="state" @close="selected = null" />
  </div>
</template>
<style scoped>
.record-table-content { display: flex; flex-direction: column; min-height: 0; flex: 1; }
.detail-toolbar { display: flex; align-items: center; gap: 12px; padding: 10px 13px; flex-shrink: 0; font-size: 12px; }
.table-scroll { flex: 1; }
.record-link { display: inline-flex; align-items: center; gap: 4px; border-radius: 3px; color: var(--primary); }
.record-link:hover { text-decoration: underline; }
.detail-table { table-layout: fixed; font-variant-numeric: tabular-nums; }
.detail-table td { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.column-resize { position: absolute; top: 0; bottom: 0; right: 0; width: 6px; cursor: col-resize; touch-action: none; }
.column-resize:hover, .column-resize:focus-visible { background: var(--primary); }
</style>
