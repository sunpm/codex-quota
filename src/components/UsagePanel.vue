<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { groupBy as groupRecords } from '@pmun/utils'
import { ChevronRight, CircleHelp, Search } from '@lucide/vue'
import { TooltipProvider, TooltipRoot, TooltipTrigger, TooltipPortal, TooltipContent } from 'reka-ui'
import type { EChartsCoreOption } from 'echarts/core'
import type { AppSnapshot, Metric, Page, UsageRecord } from '@/types'
import { basename, compareSummaries, costCardTitle, costColumnLabel, costLabel, costTooltip, dateText, dayKey, metricValue, money, percent, shortTokens, shiftDay, startOfDay, summarize, summaryMoney } from '@/lib/usage'
import { overviewGroupBy, syncOverviewToDetails, usageRanges, useUsageFilters, type UsageSort } from '@/lib/usage-filters'
import { compareTableNumbers, useTablePagination } from '@/lib/table'
import { Button } from '@/components/ui/button'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import Chart from './Chart.vue'
import SlidingSelection from './SlidingSelection.vue'
import UsageDetailDialog from './UsageDetailDialog.vue'
import TablePagination from './TablePagination.vue'
import TableSortButton from './TableSortButton.vue'

const props = defineProps<{ state: AppSnapshot; page: Page; clock: { now: number; calendar: string } }>()
const emit = defineEmits<{ navigate: [page: Page] }>()
const { view, period, metric, sort, direction, model, search, start, end } = useUsageFilters(() => props.page)
const groupBy = overviewGroupBy
const grouping = computed(() => props.page === 'details' ? view.value : groupBy.value)
const detail = ref<{ title: string; records: UsageRecord[] } | null>(null)
const tableScroll = ref<HTMLElement | null>(null)
watch([() => props.page, view], () => { detail.value = null })
watch(grouping, value => { if (value !== 'session' && sort.value === 'last') { sort.value = metric.value; direction.value = 'desc' } }, { immediate: true })
const range = computed(() => {
  const today = startOfDay(new Date(props.clock.now * 1000))
  if (period.value === 'all') return { from: 0, to: props.clock.now + 1, days: 0 }
  let from = today, to = shiftDay(today, 1)
  if (period.value === 'yesterday') { from = shiftDay(today, -1); to = today }
  else if (period.value === '7' || period.value === '30') from = shiftDay(today, 1 - Number(period.value))
  else if (period.value === 'custom') { from = new Date(`${start.value}T00:00:00`); to = shiftDay(new Date(`${end.value}T00:00:00`), 1) }
  const days = Math.round((Date.UTC(to.getFullYear(), to.getMonth(), to.getDate()) - Date.UTC(from.getFullYear(), from.getMonth(), from.getDate())) / 86400000)
  return { from: from.getTime() / 1000, to: Math.min(to.getTime() / 1000, props.clock.now + 1), days }
})
const rangeText = computed(() => {
  if (period.value === 'all') return ''
  if (period.value === 'custom') return `${start.value} — ${end.value}`
  const first = dayKey(new Date(range.value.from * 1000))
  const last = dayKey(shiftDay(new Date(range.value.from * 1000), Math.max(0, range.value.days - 1)))
  return first === last ? first : `${first} — ${last}`
})
const availableRecords = computed(() => props.state.usage.records.filter(record => record.service === 'codex' && record.date <= props.clock.now))
const models = computed(() => [...new Set([...availableRecords.value.map(record => record.model), ...(model.value === 'all' ? [] : [model.value])])].sort())
const inModel = (record: UsageRecord) => model.value === 'all' || record.model === model.value
const records = computed(() => availableRecords.value.filter(record => record.date >= range.value.from && record.date < range.value.to && inModel(record)))
const total = computed(() => summarize(records.value))
const previous = computed(() => {
  if (!range.value.days) return null
  const from = shiftDay(new Date(range.value.from * 1000), -range.value.days).getTime() / 1000
  const to = shiftDay(new Date(range.value.to * 1000), -range.value.days).getTime() / 1000
  return { from, to, total: summarize(availableRecords.value.filter(record => record.date >= from && record.date < to && inModel(record))) }
})
function changeText(kind: Metric) {
  if (props.state.usage.scannedAt === null || !previous.value || kind === 'cost' && (total.value.unpriced || previous.value.total.unpriced)) return null
  const current = metricValue(total.value, kind), before = metricValue(previous.value.total, kind)
  const delta = current - before
  const amount = kind === 'tokens' ? `${shortTokens(Math.abs(delta))} Tokens` : money(String(Math.abs(delta)))
  const title = `上期：${kind === 'tokens' ? `${before.toLocaleString('zh-CN')} Tokens` : costTooltip(previous.value.total)}`
  if (!delta) return { text: '较上期持平', title, direction: 'unchanged' }
  const direction = delta > 0 ? 'increase' : 'decrease'
  if (!before) return { text: `+${amount}`, title, direction }
  const sign = delta > 0 ? '+' : '−'
  return { text: `${sign}${amount}（${(Math.abs(delta) / before * 100).toFixed(1)}%）`, title, direction }
}
const byHour = computed(() => period.value === 'today' || period.value === 'yesterday')
const buckets = computed(() => {
  const values = groupRecords(records.value, record => {
    const date = new Date(record.date * 1000)
    return byHour.value ? `${String(date.getHours()).padStart(2, '0')}:00` : dayKey(date)
  })
  if (byHour.value) for (let hour = 0; hour < 24; hour++) values[`${String(hour).padStart(2, '0')}:00`] ??= []
  else if (period.value !== 'all' && range.value.days <= 366) for (let day = new Date(range.value.from * 1000); day.getTime() / 1000 < range.value.to; day = shiftDay(day, 1)) values[dayKey(day)] ??= []
  return Object.entries(values).sort(([a], [b]) => a.localeCompare(b)).map(([key, records]) => ({ key, total: summarize(records) }))
})
const trend = computed<EChartsCoreOption>(() => ({
  grid: { left: 54, right: 62, top: 30, bottom: 35 },
  legend: { top: 0, selectedMode: false },
  tooltip: { trigger: 'axis', renderMode: 'richText', formatter: (params: { dataIndex: number }[]) => {
    const bucket = buckets.value[params[0]?.dataIndex ?? -1]
    if (!bucket) return ''
    const date = byHour.value ? `${dayKey(new Date(range.value.from * 1000))} ${bucket.key}` : bucket.key
    return `${date}\n${bucket.total.tokens.toLocaleString('zh-CN')} Tokens\n${costLabel(bucket.total)}：${summaryMoney(bucket.total)}${bucket.total.unpriced ? `\n${bucket.total.unpriced} 条未定价` : ''}`
  } },
  xAxis: { type: 'category', data: buckets.value.map(bucket => bucket.key), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { hideOverlap: true, formatter: (value: string) => byHour.value ? value : value.slice(5).replace('-', '/') } },
  yAxis: [
    { type: 'value', name: 'Tokens', min: 0, splitNumber: 3, axisLabel: { formatter: shortTokens }, splitLine: { lineStyle: { color: '#88888820' } } },
    { type: 'value', name: `${costLabel(total.value)} ($)`, min: 0, splitNumber: 3, axisLabel: { formatter: (value: number) => `$${value}` }, splitLine: { show: false } },
  ],
  series: [
    { name: 'Tokens', type: 'bar', barMaxWidth: 30, itemStyle: { borderRadius: [3, 3, 0, 0] }, data: buckets.value.map(bucket => bucket.total.tokens) },
    { name: costLabel(total.value), type: 'line', yAxisIndex: 1, symbol: 'circle', symbolSize: 5, connectNulls: false, data: buckets.value.map(bucket => bucket.total.count && !bucket.total.priced ? null : metricValue(bucket.total, 'cost')) },
  ],
}))
function grouped(kind: string) {
  const values = new Map<string, UsageRecord[]>()
  for (const record of records.value) {
    const key = kind === 'session' ? record.session : kind === 'project' ? props.state.usage.projectRoots[record.project] ?? record.project : record.model
    const bucket = values.get(key) ?? []; bucket.push(record); values.set(key, bucket)
  }
  return [...values].map(([key, records]) => {
    const project = props.state.usage.projectRoots[records[0]!.project] ?? records[0]!.project
    return { key, project, records, total: summarize(records), name: kind === 'session' ? basename(project) : kind === 'project' ? basename(key) : key, subtitle: kind === 'session' ? key.slice(0, 12) : kind === 'project' ? key : '', last: records.reduce((latest, record) => Math.max(latest, record.date), 0) }
  }).sort((a, b) => compareSummaries(a.total, b.total, metric.value))
}
const groups = computed(() => grouped(grouping.value).filter(group => props.page === 'overview' || !search.value.trim() || `${group.name} ${group.key} ${group.project}`.toLowerCase().includes(search.value.trim().toLowerCase())).sort((a, b) => {
  const key = sort.value
  const aValue = key === 'last' ? a.last : key === 'cost' ? (a.total.priced ? Number(a.total.amount) : null) : a.total[key]
  const bValue = key === 'last' ? b.last : key === 'cost' ? (b.total.priced ? Number(b.total.amount) : null) : b.total[key]
  return compareTableNumbers(aValue, bValue, direction.value) || a.key.localeCompare(b.key)
}))
const { page: tablePage, pageSize, pageRows } = useTablePagination(groups, 'usage.summary.pageSize.v1')
watch([() => props.page, grouping, period, model, search, start, end, sort, direction], () => { tablePage.value = 1 })
watch([tablePage, pageSize, grouping, period, model, search, start, end, sort, direction], () => { tableScroll.value?.scrollTo(0, 0) }, { flush: 'post' })
function selectSort(key: UsageSort) {
  direction.value = sort.value === key && direction.value === 'desc' ? 'asc' : 'desc'
  sort.value = key
  if (key === 'tokens' || key === 'cost') metric.value = key
}
const sortState = (key: UsageSort) => sort.value === key ? direction.value === 'asc' ? 'ascending' : 'descending' : 'none'
const summaryTotal = computed(() => props.page === 'details' && search.value.trim() ? summarize(groups.value.flatMap(group => group.records)) : total.value)
const tokenColumnWidth = computed(() => `calc(${groups.value.reduce((width, group) => Math.max(width, group.total.tokens.toLocaleString('zh-CN').length), 14)}ch + 26px)`)
const topSessions = computed(() => grouped('session').slice(0, 5))
const heatmap = computed<EChartsCoreOption>(() => {
  const last = startOfDay(new Date(props.clock.now * 1000)), first = shiftDay(last, -370)
  const days = groupRecords(availableRecords.value.filter(inModel), record => dayKey(new Date(record.date * 1000)))
  const data = Array.from({ length: 371 }, (_, index) => {
    const day = shiftDay(first, index)
    const summary = summarize(days[dayKey(day)] ?? [])
    return { value: [dayKey(day), summary.tokens], summary }
  })
  return {
    tooltip: { renderMode: 'richText', formatter: (params: { dataIndex: number }) => {
      const day = data[params.dataIndex]!, summary = day.summary
      return `${day.value[0]}\n${summary.tokens.toLocaleString('zh-CN')} Tokens\n${costLabel(summary)}：${summaryMoney(summary)}${summary.unpriced ? `\n${summary.unpriced} 条未定价` : ''}`
    } },
    visualMap: { show: false, min: 0, max: Math.max(1, ...data.map(item => Number(item.value[1]))), inRange: { color: ['#88888815', '#a3d1ca', '#679e94', '#33786c'] } },
    calendar: { top: 28, left: 32, right: 8, bottom: 4, range: [dayKey(first), dayKey(last)], cellSize: ['auto', 15], splitLine: { show: false }, itemStyle: { borderWidth: 2, borderColor: 'transparent' }, yearLabel: { show: false }, dayLabel: { firstDay: 1, nameMap: 'ZH', fontSize: 10, color: '#888' }, monthLabel: { nameMap: 'ZH', color: '#888', fontSize: 11 } },
    series: [{ type: 'heatmap', coordinateSystem: 'calendar', data }],
  }
})
function showDetail(name: string, items: UsageRecord[]) { detail.value = { title: name, records: items } }
function openInDetails(targetView: 'session' | 'project') { syncOverviewToDetails(targetView); emit('navigate', 'details') }
</script>

<template>
  <div class="usage-page" :class="{ 'table-page': page !== 'overview' }">
    <div class="usage-filters">
      <div class="filter-bar">
        <SlidingSelection v-slot="{ highlight }" :selection="period" class="segmented" role="group" aria-label="日期范围">
          <component :is="highlight ? 'span' : 'label'" v-for="item in usageRanges" :key="item.value" class="segment-option" :data-selected="period === item.value"><input v-if="!highlight" v-model="period" class="sr-only" type="radio" name="date-range" :value="item.value" />{{ item.label }}</component>
        </SlidingSelection>
        <div class="filter-spacer" />
        <label class="sr-only" for="model-filter">模型</label>
        <NativeSelect id="model-filter" :model-value="model" @change="model = ($event.target as HTMLSelectElement).value"><NativeSelectOption value="all">全部模型</NativeSelectOption><NativeSelectOption v-for="item in models" :key="item" :value="item">{{ item }}</NativeSelectOption></NativeSelect>
      </div>
      <div v-if="period === 'custom'" class="date-range"><label>开始 <input v-model="start" type="date" :max="end" /></label><span>—</span><label>结束 <input v-model="end" type="date" :min="start" :max="dayKey(new Date(props.clock.now * 1000))" /></label></div>
      <div class="source-line">
        <div class="source-label">
          <span :title="state.usage.source">本机日志<span v-if="rangeText"> · {{ rangeText }}</span></span>
          <TooltipProvider :delay-duration="200"><TooltipRoot>
            <TooltipTrigger as-child><Button variant="ghost" size="icon-xs" class="source-info-trigger" aria-label="统计范围说明"><CircleHelp :size="12" /></Button></TooltipTrigger>
            <TooltipPortal><TooltipContent class="source-info-tooltip" side="bottom" align="start" :side-offset="6">包含本机已采集历史，可能来自多个账号；不代表当前账号或其他设备的全部用量。</TooltipContent></TooltipPortal>
          </TooltipRoot></TooltipProvider>
        </div>
        <span v-if="state.usage.scannedAt">扫描于 {{ dateText(state.usage.scannedAt) }}</span>
      </div>
    </div>
    <div v-for="warning in state.usage.warnings" :key="warning" class="notice warning" role="status">{{ warning }}</div>
    <div class="usage-summary">
      <div class="summary-strip" :class="{ compact: page !== 'overview' }">
        <div><span class="metric-label">总 Tokens</span><strong :title="state.usage.scannedAt === null ? '尚未读取本机日志' : undefined">{{ state.usage.scannedAt ? summaryTotal.tokens.toLocaleString('zh-CN') : '—' }}</strong><span v-if="page === 'overview' && changeText('tokens')" class="comparison" :data-direction="changeText('tokens')!.direction" :title="changeText('tokens')!.title">{{ changeText('tokens')!.text }}</span></div>
        <div :title="costCardTitle(summaryTotal)"><span class="metric-label">{{ costLabel(summaryTotal) }} <small class="metric-note">· API 等价估算</small></span><strong :class="{ 'unpriced-text': state.usage.scannedAt && summaryTotal.count && !summaryTotal.priced }">{{ state.usage.scannedAt ? summaryMoney(summaryTotal) : '—' }}</strong><div v-if="page === 'overview' && changeText('cost') || state.usage.scannedAt && summaryTotal.unpriced" class="metric-meta"><span v-if="page === 'overview' && changeText('cost')" class="comparison" :data-direction="changeText('cost')!.direction" :title="changeText('cost')!.title">{{ changeText('cost')!.text }}</span><span v-if="state.usage.scannedAt && summaryTotal.unpriced" class="unpriced-text">{{ summaryTotal.unpriced.toLocaleString('zh-CN') }} 条未定价</span></div></div>
      </div>
      <div class="summary-details"><span>{{ state.usage.scannedAt ? summaryTotal.sessions.toLocaleString() : '—' }} 个对话</span><span title="缓存命中 ÷ 全部输入">缓存命中率 {{ state.usage.scannedAt ? percent(summaryTotal.hitRate) : '—' }}</span><span v-if="page === 'overview' && state.usage.scannedAt !== null && previous" class="comparison-range">上期 {{ dateText(previous.from) }} — {{ dateText(previous.to - 1) }}</span></div>
    </div>
    <template v-if="page === 'overview'">
      <section class="surface chart-section"><div class="section-heading"><h2>用量趋势</h2></div><Chart v-if="records.length" :option="trend" label="当前期间用量趋势：柱形为 Tokens（左轴），折线为费用（右轴）" :animations="state.settings.animations" /><div v-else class="empty-state chart-empty">{{ state.usage.scannedAt ? '此时间范围没有用量记录' : '尚未读取本机日志' }}</div></section>
      <div class="analysis-grid">
        <section class="surface"><div class="section-heading"><h2>用量构成</h2></div><div v-if="state.usage.scannedAt !== null" class="composition">
          <div v-for="item in [{ label: '新增输入', value: total.input }, { label: '输出', value: total.output }, { label: '缓存命中', value: total.cached }, { label: '缓存写入', value: total.cacheWrite }]" :key="item.label" class="composition-row"><span>{{ item.label }}</span><div class="composition-track"><div :style="{ width: `${total.tokens ? item.value / total.tokens * 100 : 0}%` }" /></div><strong :title="item.value.toLocaleString()">{{ shortTokens(item.value) }}</strong></div>
        </div><div v-else class="empty-state">尚未读取本机日志</div></section>
        <section class="surface"><div class="section-heading"><h2>高消耗对话</h2><div class="heading-actions"><SlidingSelection v-slot="{ highlight }" :selection="metric" class="segmented" role="group" aria-label="高消耗对话排序指标"><component :is="highlight ? 'span' : 'label'" v-for="item in [{ value: 'tokens', label: 'Tokens' }, { value: 'cost', label: costLabel(total) }]" :key="item.value" class="segment-option" :data-selected="metric === item.value"><input v-if="!highlight" v-model="metric" class="sr-only" type="radio" name="top-session-metric" :value="item.value" @change="sort = metric; direction = 'desc'" />{{ item.label }}</component></SlidingSelection><Button variant="ghost" size="sm" @click="openInDetails('session')">在明细中查看<ChevronRight :size="13" /></Button></div></div><div v-if="!topSessions.length" class="empty-state">{{ state.usage.scannedAt === null ? '尚未读取本机日志' : '暂无记录' }}</div><button v-for="group in topSessions" :key="group.key" class="ranking-row" @click="showDetail(group.name, group.records)"><span :title="group.key">{{ group.name }}<small>{{ dateText(group.last) }} · {{ group.subtitle }}</small></span><strong :class="{ 'unpriced-text': metric === 'cost' && group.total.count && !group.total.priced }" :title="metric === 'tokens' ? group.total.tokens.toLocaleString() : costTooltip(group.total)">{{ metric === 'tokens' ? shortTokens(group.total.tokens) : summaryMoney(group.total) }}<small v-if="metric === 'cost' && group.total.priced && group.total.unpriced" class="unpriced-inline">含未定价</small></strong><ChevronRight :size="14" /></button></section>
      </div>
    </template>
    <section class="surface table-surface" :class="{ 'overview-table': page === 'overview' }">
      <div class="section-heading">
        <template v-if="page === 'overview'">
          <h2>{{ grouping === 'project' ? '项目汇总' : '模型汇总' }} <span class="count">{{ state.usage.scannedAt === null ? '—' : groups.length }}</span></h2>
          <NativeSelect :model-value="groupBy" aria-label="汇总分组" @change="groupBy = (($event.target as HTMLSelectElement).value as 'model' | 'project')"><NativeSelectOption value="model">按模型</NativeSelectOption><NativeSelectOption value="project">按项目</NativeSelectOption></NativeSelect>
        </template>
        <template v-else>
          <SlidingSelection v-slot="{ highlight }" :selection="view" class="segmented" role="group" aria-label="明细分组">
            <component :is="highlight ? 'span' : 'label'" v-for="item in [{ value: 'session', label: '按对话' }, { value: 'project', label: '按项目' }]" :key="item.value" class="segment-option" :data-selected="view === item.value"><input v-if="!highlight" v-model="view" class="sr-only" type="radio" name="detail-view" :value="item.value" @change="search = ''" />{{ item.label }}</component>
          </SlidingSelection>
          <label class="search-box"><Search :size="14" /><input v-model="search" :placeholder="view === 'session' ? '搜索对话或项目' : '搜索项目'" aria-label="搜索" /></label>
        </template>
      </div>
      <div ref="tableScroll" class="table-scroll"><table class="usage-table" :class="{ 'project-table': grouping === 'project' }" :style="{ '--tokens-column-width': tokenColumnWidth }">
        <thead><tr>
          <th class="name-column">{{ grouping === 'session' ? '对话' : grouping === 'project' ? '项目' : '模型' }}</th>
          <th v-if="grouping !== 'model'" class="secondary-column" :class="{ 'time-column': grouping === 'session' }" :aria-sort="grouping === 'session' ? sortState('last') : undefined"><TableSortButton v-if="grouping === 'session'" label="最近用量" :active="sort === 'last'" :direction="direction" @click="selectSort('last')" /><template v-else>目录</template></th>
          <th class="number count-column" :aria-sort="sortState('count')"><TableSortButton label="记录数" :active="sort === 'count'" :direction="direction" @click="selectSort('count')" /></th>
          <th class="number tokens-column" :aria-sort="sortState('tokens')"><TableSortButton label="Tokens" :active="sort === 'tokens'" :direction="direction" @click="selectSort('tokens')" /></th>
          <th class="number cost-column" :aria-sort="sortState('cost')"><TableSortButton :label="costColumnLabel(summaryTotal)" :active="sort === 'cost'" :direction="direction" @click="selectSort('cost')" /></th>
          <th class="number share-column" :title="metric === 'tokens' ? 'Tokens 占比' : summaryTotal.unpriced ? '统计范围内含未定价记录，不计算费用占比' : '费用占比'">{{ metric === 'tokens' ? 'Tokens 占比' : '费用占比' }}</th>
          <th class="number cache-column" :aria-sort="sortState('hitRate')"><TableSortButton label="缓存命中率" :active="sort === 'hitRate'" :direction="direction" @click="selectSort('hitRate')" /></th>
        </tr></thead>
        <tbody><tr v-for="group in pageRows" :key="group.key">
          <td><button class="table-link" :title="group.key" @click="showDetail(group.name, group.records)"><span>{{ group.name }}<small v-if="grouping === 'session'">{{ group.subtitle }}</small></span><ChevronRight :size="13" /></button></td>
          <td v-if="grouping !== 'model'" class="muted secondary-column"><span :title="grouping === 'session' ? dateText(group.last, true) : group.subtitle">{{ grouping === 'session' ? dateText(group.last) : group.subtitle }}</span></td>
          <td class="number" :title="group.total.count.toLocaleString()">{{ group.total.count.toLocaleString() }}</td>
          <td class="number">{{ group.total.tokens.toLocaleString('zh-CN') }}</td>
          <td class="number" :title="costTooltip(group.total)"><span :class="{ 'unpriced-text': group.total.count && !group.total.priced }">{{ summaryMoney(group.total) }}</span><small v-if="group.total.priced && group.total.unpriced" class="unpriced-inline">含未定价</small></td>
          <td class="number muted" :title="metric === 'cost' && summaryTotal.unpriced ? '统计范围内含未定价记录，不计算费用占比' : undefined">{{ metric === 'cost' && summaryTotal.unpriced ? '—' : metricValue(summaryTotal, metric) ? percent(metricValue(group.total, metric) / metricValue(summaryTotal, metric)) : '—' }}</td>
          <td class="number muted">{{ percent(group.total.hitRate) }}</td>
        </tr></tbody>
      </table><div v-if="!groups.length" class="empty-state">{{ state.usage.scannedAt === null ? '尚未读取本机日志' : search ? '没有匹配的记录' : '此时间范围没有用量记录' }}</div></div>
      <TablePagination v-model:page="tablePage" v-model:page-size="pageSize" :total="groups.length" />
    </section>
    <section v-if="page === 'overview'" class="surface heatmap-section"><div class="section-heading"><h2>最近 53 周</h2></div><Chart v-if="state.usage.scannedAt !== null" :option="heatmap" label="最近53周每日 Tokens 用量热力图" :height="150" :animations="false" /><div v-else class="empty-state">尚未读取本机日志</div><p v-if="state.usage.scannedAt !== null" class="heatmap-legend">低 <span class="heatmap-scale" /> 高</p></section>
    <UsageDetailDialog v-if="detail" :title="detail.title" :records="detail.records" :state="state" @close="detail = null" />
  </div>
</template>
