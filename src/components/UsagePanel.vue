<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { groupBy as groupRecords } from '@pmun/utils'
import { ChevronRight, CircleHelp, Search } from '@lucide/vue'
import { TooltipProvider, TooltipRoot, TooltipTrigger, TooltipPortal, TooltipContent } from 'reka-ui'
import type { EChartsCoreOption } from 'echarts/core'
import type { AppSnapshot, Metric, Page, UsageRecord } from '@/types'
import { basename, compareSummaries, costCardTitle, costColumnLabel, costLabel, costTooltip, dateText, dateTimeKey, dayKey, metricValue, money, percent, serviceName, shortTokens, shiftDay, startOfDay, summarize, summaryMoney } from '@/lib/usage'
import { overviewGroupBy, parseUsageDateTime, syncOverviewToDetails, usageRanges, usageService, useUsageFilters, type UsageSort } from '@/lib/usage-filters'
import { compareTableNumbers, useTablePagination } from '@/lib/table'
import TablePagination from './TablePagination.vue'
import TableSortButton from './TableSortButton.vue'
import UsageRecordTable from './UsageRecordTable.vue'
import DetailColumnsMenu from './DetailColumnsMenu.vue'
import { Button } from '@/components/ui/button'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import Chart from './Chart.vue'
import SlidingSelection from './SlidingSelection.vue'
import UsageDetailDialog from './UsageDetailDialog.vue'
import antigravityIcon from '@/assets/antigravity.svg'

const props = defineProps<{ state: AppSnapshot; page: Page; clock: { now: number; calendar: string } }>()
const emit = defineEmits<{ navigate: [page: Page] }>()
const { view, period, metric, sort, direction, model, search, start, end } = useUsageFilters(() => props.page)
const groupBy = overviewGroupBy
const trendMetric = ref<Metric>('tokens')
const services = [{ id: 'codex', name: 'Codex', color: '#3279bd' }, { id: 'antigravity', name: 'Antigravity', color: '#448d86' }] as const
const selectedServices = computed(() => services.filter(service => usageService.value === 'all' || service.id === usageService.value))
const grouping = computed(() => props.page === 'details' ? view.value : groupBy.value)
const detail = ref<{ title: string; records: UsageRecord[] } | null>(null)
const tableScroll = ref<HTMLElement | null>(null)
watch([() => props.page, grouping, usageService], () => { detail.value = null })
watch(grouping, value => { if (value !== 'session' && sort.value === 'last') { sort.value = metric.value; direction.value = 'desc' } }, { immediate: true })
const customRange = computed(() => {
  const from = parseUsageDateTime(start.value), to = parseUsageDateTime(end.value)
  return from !== null && to !== null && from < to ? { from, to } : null
})
const range = computed(() => {
  const today = startOfDay(new Date(props.clock.now * 1000))
  if (period.value === 'all') return { from: 0, to: props.clock.now + 1, days: 0 }
  if (period.value === '24h') return { from: props.clock.now - 86400, to: props.clock.now, days: 0 }
  if (period.value === 'custom') return { from: customRange.value?.from ?? 0, to: Math.min(customRange.value?.to ?? 0, props.clock.now + 1), days: 0 }
  let from = today, to = shiftDay(today, 1)
  if (period.value === 'yesterday') { from = shiftDay(today, -1); to = today }
  else if (period.value === '7' || period.value === '30') from = shiftDay(today, 1 - Number(period.value))
  const days = Math.round((Date.UTC(to.getFullYear(), to.getMonth(), to.getDate()) - Date.UTC(from.getFullYear(), from.getMonth(), from.getDate())) / 86400000)
  return { from: from.getTime() / 1000, to: Math.min(to.getTime() / 1000, props.clock.now + 1), days }
})
const rangeText = computed(() => {
  if (period.value === 'all') return ''
  if (period.value === 'custom') return customRange.value ? `${start.value.replace('T', ' ')} — ${end.value.replace('T', ' ')}` : ''
  if (period.value === '24h') return `${dateTimeKey(new Date(range.value.from * 1000)).replace('T', ' ')} — ${dateTimeKey(new Date(range.value.to * 1000)).replace('T', ' ')}`
  const first = dayKey(new Date(range.value.from * 1000))
  const last = dayKey(shiftDay(new Date(range.value.from * 1000), Math.max(0, range.value.days - 1)))
  return first === last ? first : `${first} — ${last}`
})
const availableRecords = computed(() => props.state.usage.records.filter(record => (usageService.value === 'all' || record.service === usageService.value) && record.date <= props.clock.now))
const hasReadableUsage = computed(() => props.state.usage.scannedAt !== null)
const models = computed(() => [...new Set([...availableRecords.value.map(record => record.model), ...(model.value === 'all' ? [] : [model.value])])].sort())
const inModel = (record: UsageRecord) => model.value === 'all' || record.model === model.value
const records = computed(() => availableRecords.value.filter(record => record.date >= range.value.from && record.date < range.value.to && inModel(record)))
const total = computed(() => summarize(records.value))
const previous = computed(() => {
  if (period.value === 'all' || range.value.to <= range.value.from) return null
  const duration = period.value === 'custom' ? customRange.value!.to - customRange.value!.from : 86400
  const from = range.value.days ? shiftDay(new Date(range.value.from * 1000), -range.value.days).getTime() / 1000 : range.value.from - duration
  const to = range.value.days ? shiftDay(new Date(range.value.to * 1000), -range.value.days).getTime() / 1000 : range.value.to - duration
  return { from, to, total: summarize(availableRecords.value.filter(record => record.date >= from && record.date < to && inModel(record))) }
})
function changeText(kind: Metric) {
  if (props.state.usage.scannedAt === null || !previous.value || kind === 'cost' && total.value.count > 0 && !total.value.priced) return null
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
const byHour = computed(() => period.value === 'today' || period.value === 'yesterday' || period.value === '24h' || period.value === 'custom' && customRange.value !== null && customRange.value.to - customRange.value.from <= 86400)
const hourlyAcrossDays = computed(() => byHour.value && dayKey(new Date(range.value.from * 1000)) !== dayKey(new Date((range.value.to - 0.001) * 1000)))
const buckets = computed(() => {
  const values = groupRecords(records.value, record => {
    const date = new Date(record.date * 1000)
    if (!byHour.value) return dayKey(date)
    date.setMinutes(0, 0, 0)
    return String(date.getTime() / 1000)
  })
  if (byHour.value) {
    const first = new Date(range.value.from * 1000); first.setMinutes(0, 0, 0)
    const to = period.value === 'today' || period.value === 'yesterday' ? shiftDay(startOfDay(first), 1).getTime() / 1000 : range.value.to
    for (let hour = first.getTime() / 1000; hour < to; hour += 3600) values[String(hour)] ??= []
  } else if (period.value !== 'all' && range.value.to - range.value.from <= 366 * 86400) {
    for (let day = startOfDay(new Date(range.value.from * 1000)); day.getTime() / 1000 < range.value.to; day = shiftDay(day, 1)) values[dayKey(day)] ??= []
  }
  return Object.entries(values).sort(([a], [b]) => byHour.value ? Number(a) - Number(b) : a.localeCompare(b)).map(([key, records]) => ({
    key, total: summarize(records),
    codex: summarize(records.filter(record => record.service === 'codex')),
    antigravity: summarize(records.filter(record => record.service === 'antigravity')),
  }))
})
const trend = computed<EChartsCoreOption>(() => ({
  grid: { left: 54, right: 20, top: 30, bottom: 35 },
  legend: { top: 0, selectedMode: false },
  tooltip: { trigger: 'axis', renderMode: 'richText', formatter: (params: { dataIndex: number }[]) => {
    const bucket = buckets.value[params[0]?.dataIndex ?? -1]
    if (!bucket) return ''
    const date = byHour.value ? dateTimeKey(new Date(Number(bucket.key) * 1000)).replace('T', ' ') : bucket.key
    const lines = selectedServices.value.map(service => {
      const summary = bucket[service.id]
      return `${service.name}：${summary.tokens.toLocaleString('zh-CN')} Tokens · ${summaryMoney(summary)}`
    })
    return [date, ...lines, ...(selectedServices.value.length > 1 ? [`合计：${bucket.total.tokens.toLocaleString('zh-CN')} Tokens · ${summaryMoney(bucket.total)}`] : [])].join('\n')
  } },
  xAxis: { type: 'category', data: buckets.value.map(bucket => bucket.key), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { hideOverlap: true, formatter: (value: string) => byHour.value ? dateTimeKey(new Date(Number(value) * 1000)).slice(hourlyAcrossDays.value ? 5 : 11).replace('T', ' ').replace('-', '/') : value.slice(5).replace('-', '/') } },
  yAxis: { type: 'value', name: trendMetric.value === 'tokens' ? 'Tokens' : `${costLabel(total.value)} ($)`, min: 0, splitNumber: 3, axisLabel: { formatter: (value: number) => trendMetric.value === 'tokens' ? shortTokens(value) : money(String(value)) }, splitLine: { lineStyle: { color: '#88888820' } } },
  series: selectedServices.value.map(service => ({
    name: service.name, type: 'bar', stack: 'usage', barMaxWidth: 30, itemStyle: { color: service.color },
    data: buckets.value.map(bucket => {
      const summary = bucket[service.id]
      return trendMetric.value === 'cost' && summary.count && !summary.priced ? null : metricValue(summary, trendMetric.value)
    }),
  })),
}))
function grouped(kind: string) {
  const values = new Map<string, UsageRecord[]>()
  for (const record of records.value) {
    const value = kind === 'session' ? record.session : kind === 'project' ? props.state.usage.projectRoots[record.project] ?? record.project : record.model
    const key = `${record.service}:${value}`
    const bucket = values.get(key) ?? []; bucket.push(record); values.set(key, bucket)
  }
  return [...values].map(([key, records]) => {
    const project = props.state.usage.projectRoots[records[0]!.project] ?? records[0]!.project
    const first = records[0]!
    const sessionTitle = kind === 'session' && first.service === 'codex' ? props.state.usage.sessionTitles[first.session] : undefined
    return { key, project, records, total: summarize(records), name: kind === 'session' ? sessionTitle || basename(project) : kind === 'project' ? basename(project) : first.model === 'unknown' ? '未知模型' : first.model, subtitle: kind === 'session' ? `${serviceName(first.service)}${sessionTitle ? ` · ${basename(project)}` : ''} · ${first.session.slice(0, 12)}` : kind === 'project' ? `${serviceName(first.service)} · ${project || '未知目录'}` : serviceName(first.service), last: records.reduce((latest, record) => Math.max(latest, record.date), 0) }
  }).sort((a, b) => compareSummaries(a.total, b.total, metric.value))
}
const groups = computed(() => grouped(grouping.value).filter(group => props.page === 'overview' || !search.value.trim() || `${group.name} ${group.key} ${group.project}`.toLowerCase().includes(search.value.trim().toLowerCase())).sort((a, b) => {
  const key = sort.value
  const aValue = key === 'last' ? a.last : key === 'cost' ? (a.total.priced ? Number(a.total.amount) : null) : a.total[key]
  const bValue = key === 'last' ? b.last : key === 'cost' ? (b.total.priced ? Number(b.total.amount) : null) : b.total[key]
  return compareTableNumbers(aValue, bValue, direction.value) || a.key.localeCompare(b.key)
}))
const { page: tablePage, pageSize, pageRows } = useTablePagination(groups, 'usage.summary.pageSize.v1')
watch([() => props.page, grouping, usageService, period, model, search, start, end, sort, direction], () => { tablePage.value = 1 })
watch([tablePage, pageSize, grouping, usageService, period, model, search, start, end, sort, direction], () => { tableScroll.value?.scrollTo(0, 0) }, { flush: 'post' })
function selectSort(key: UsageSort) {
  direction.value = sort.value === key && direction.value === 'desc' ? 'asc' : 'desc'
  sort.value = key
  if (key === 'tokens' || key === 'cost') metric.value = key
}
const sortState = (key: UsageSort) => sort.value === key ? direction.value === 'asc' ? 'ascending' : 'descending' : 'none'
const recordView = computed(() => props.page === 'details' && view.value === 'record')
const matchingRecords = computed(() => {
  const query = search.value.trim().toLowerCase()
  return records.value.filter(record => !query || `${record.service === 'codex' ? props.state.usage.sessionTitles[record.session] ?? '' : ''} ${record.service} ${serviceName(record.service)} ${record.session} ${record.id} ${record.project} ${props.state.usage.projectRoots[record.project] ?? ''} ${record.model}`.toLowerCase().includes(query))
})
const recordFilterKey = computed(() => JSON.stringify([usageService.value, period.value, model.value, start.value, end.value, search.value]))
const summaryTotal = computed(() => recordView.value ? summarize(matchingRecords.value) : props.page === 'details' && search.value.trim() ? summarize(groups.value.flatMap(group => group.records)) : total.value)
const tokenColumnWidth = computed(() => `calc(${groups.value.reduce((width, group) => Math.max(width, group.total.tokens.toLocaleString('zh-CN').length), 14)}ch + 26px)`)
const heatmap = computed<EChartsCoreOption>(() => {
  const last = startOfDay(new Date((range.value.to - 0.001) * 1000))
  const earliest = period.value === 'all' ? records.value.reduce((date, record) => Math.min(date, record.date), range.value.to) : range.value.from
  const first = new Date(Math.min(startOfDay(new Date(earliest * 1000)).getTime(), shiftDay(last, -370).getTime()))
  const days = groupRecords(records.value, record => dayKey(new Date(record.date * 1000)))
  const data = Object.entries(days).sort(([a], [b]) => a.localeCompare(b)).map(([day, records]) => {
    const summary = summarize(records)
    return { value: [day, summary.tokens], summary }
  })
  return {
    tooltip: { renderMode: 'richText', formatter: (params: { dataIndex: number }) => {
      const day = data[params.dataIndex]!, summary = day.summary
      return `${day.value[0]}\n${summary.tokens.toLocaleString('zh-CN')} Tokens\n${costLabel(summary)}：${summaryMoney(summary)}`
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
        <SlidingSelection v-slot="{ highlight }" :selection="usageService" class="segmented service-filter" role="group" aria-label="服务筛选">
          <component :is="highlight ? 'span' : 'label'" class="segment-option" :data-selected="usageService === 'all'"><input v-if="!highlight" v-model="usageService" class="sr-only" type="radio" name="usage-service" value="all" aria-label="全部服务" />全部</component>
          <component :is="highlight ? 'span' : 'label'" v-for="service in services" :key="service.id" class="segment-option service-option" :data-selected="usageService === service.id" :title="service.name">
            <input v-if="!highlight" v-model="usageService" class="sr-only" type="radio" name="usage-service" :value="service.id" :aria-label="service.name" />
            <span v-if="service.id === 'codex'" class="service-icon codex-icon" aria-hidden="true" />
            <img v-else class="service-icon" :src="antigravityIcon" alt="" aria-hidden="true" />
          </component>
        </SlidingSelection>
        <SlidingSelection v-slot="{ highlight }" :selection="period" class="segmented" role="group" aria-label="时间范围">
          <component :is="highlight ? 'span' : 'label'" v-for="item in usageRanges" :key="item.value" class="segment-option" :data-selected="period === item.value"><input v-if="!highlight" v-model="period" class="sr-only" type="radio" name="date-range" :value="item.value" />{{ item.label }}</component>
        </SlidingSelection>
        <div class="filter-spacer" />
        <label class="sr-only" for="model-filter">模型</label>
        <NativeSelect id="model-filter" :model-value="model" @change="model = ($event.target as HTMLSelectElement).value"><NativeSelectOption value="all">全部模型</NativeSelectOption><NativeSelectOption v-for="item in models" :key="item" :value="item">{{ item }}</NativeSelectOption></NativeSelect>
      </div>
      <template v-if="period === 'custom'">
        <div class="date-range"><label>开始 <input v-model="start" type="datetime-local" :max="end" required :aria-invalid="!customRange" :aria-describedby="!customRange ? 'usage-range-error' : undefined" /></label><span>—</span><label>结束 <input v-model="end" type="datetime-local" :min="start" required :aria-invalid="!customRange" :aria-describedby="!customRange ? 'usage-range-error' : undefined" /></label></div>
        <p v-if="!customRange" id="usage-range-error" class="date-range-error" role="alert">请输入完整的开始、结束时间，且结束时间须晚于开始时间。</p>
      </template>
      <div class="source-line">
        <div class="source-label">
          <span :title="state.usage.source">本机日志<span v-if="rangeText"> · {{ rangeText }}</span></span>
          <TooltipProvider :delay-duration="200"><TooltipRoot>
            <TooltipTrigger as-child><Button variant="ghost" size="icon-xs" class="source-info-trigger" aria-label="统计范围说明"><CircleHelp :size="12" /></Button></TooltipTrigger>
            <TooltipPortal><TooltipContent class="source-info-tooltip" side="bottom" align="start" :side-offset="6">包含本机已采集历史，可能来自多个账号；不代表当前账号或其他设备的全部用量。时间按本地时区计算，包含开始、不包含结束。</TooltipContent></TooltipPortal>
          </TooltipRoot></TooltipProvider>
        </div>
      </div>
    </div>
    <div v-if="page === 'overview'" class="summary-cards">
      <div class="surface summary-card tokens-card">
        <div class="card-header">
          <span class="metric-label">总 Tokens</span>
          <span v-if="changeText('tokens')" class="comparison-badge" :data-direction="changeText('tokens')!.direction" :title="changeText('tokens')!.title">{{ changeText('tokens')!.text }}</span>
        </div>
        <strong class="card-value" :title="state.usage.scannedAt === null ? '尚未读取本机日志' : undefined">{{ hasReadableUsage ? summaryTotal.tokens.toLocaleString('zh-CN') : '—' }}</strong>
        <div class="token-breakdown">
          <div v-for="item in [{ label: '新增输入', value: total.input, known: total.inputKnown }, { label: '输出', value: total.output, known: total.outputKnown }, { label: '缓存命中', value: total.cached, known: total.cachedKnown }, { label: '缓存写入', value: total.cacheWrite, known: total.cacheWriteKnown }]" :key="item.label" class="breakdown-item">
            <span class="breakdown-label">{{ item.label }}</span>
            <strong :title="hasReadableUsage ? item.value.toLocaleString('zh-CN') : undefined">{{ !hasReadableUsage || !item.known && !item.value ? '—' : shortTokens(item.value) }}</strong>
          </div>
        </div>
      </div>
      <div class="surface summary-card cost-card" :title="costCardTitle(summaryTotal)">
        <div class="card-header">
          <span class="metric-label">{{ costLabel(summaryTotal) }}</span>
          <span v-if="changeText('cost')" class="comparison-badge" :data-direction="changeText('cost')!.direction" :title="changeText('cost')!.title">{{ changeText('cost')!.text }}</span>
        </div>
        <strong class="card-value" :class="{ 'unpriced-text': state.usage.scannedAt && summaryTotal.count && !summaryTotal.priced }">{{ hasReadableUsage ? summaryMoney(summaryTotal) : '—' }}</strong>
        <div class="card-footer">
          <span>API 等价估算</span>
          <span v-if="state.usage.scannedAt !== null && previous" class="comparison-range">上期 {{ dateText(previous.from) }} — {{ dateText(previous.to - (range.days ? 1 : 0)) }}</span>
        </div>
      </div>
      <div class="surface summary-card efficiency-card">
        <div class="card-header">
          <span class="metric-label" title="缓存命中 ÷ 全部输入">缓存命中率</span>
          <span class="card-badge">{{ hasReadableUsage ? `${summaryTotal.sessions.toLocaleString('zh-CN')} 个对话` : '—' }}</span>
        </div>
        <strong class="card-value">{{ state.usage.scannedAt ? percent(summaryTotal.hitRate) : '—' }}</strong>
        <div class="card-footer efficiency-footer">
          <div class="quota-track hit-rate-track" aria-hidden="true"><div :style="{ width: `${Math.min(100, Math.max(0, (summaryTotal.hitRate ?? 0) * 100))}%` }" /></div>
          <div class="efficiency-meta"><span>缓存命中 ÷ 全部输入</span><span>{{ hasReadableUsage ? `${summaryTotal.count.toLocaleString('zh-CN')} 条记录` : '—' }}</span></div>
        </div>
      </div>
    </div>
    <div v-else class="surface summary-bar">
      <div class="summary-bar-item"><span class="metric-label">总 Tokens</span><strong>{{ hasReadableUsage ? summaryTotal.tokens.toLocaleString('zh-CN') : '—' }}</strong></div>
      <div class="summary-bar-item" :title="costCardTitle(summaryTotal)"><span class="metric-label">{{ costLabel(summaryTotal) }}</span><strong :class="{ 'unpriced-text': state.usage.scannedAt && summaryTotal.count && !summaryTotal.priced }">{{ hasReadableUsage ? summaryMoney(summaryTotal) : '—' }}</strong><small class="metric-note">API 等价估算</small></div>
      <div class="summary-bar-item"><span class="metric-label">对话数</span><strong>{{ hasReadableUsage ? summaryTotal.sessions.toLocaleString('zh-CN') : '—' }}</strong></div>
      <div class="summary-bar-item" title="缓存命中 ÷ 全部输入"><span class="metric-label">缓存命中率</span><strong>{{ state.usage.scannedAt ? percent(summaryTotal.hitRate) : '—' }}</strong></div>
    </div>
    <section v-if="page === 'overview'" class="surface chart-section">
      <div class="section-heading">
        <h2>用量趋势</h2>
        <div class="heading-actions">
          <SlidingSelection v-slot="{ highlight }" :selection="trendMetric" class="segmented" role="group" aria-label="趋势指标">
            <component :is="highlight ? 'span' : 'label'" v-for="item in [{ value: 'tokens', label: 'Tokens' }, { value: 'cost', label: '费用' }]" :key="item.value" class="segment-option" :data-selected="trendMetric === item.value"><input v-if="!highlight" v-model="trendMetric" class="sr-only" type="radio" name="trend-metric" :value="item.value" />{{ item.label }}</component>
          </SlidingSelection>
        </div>
      </div>
      <Chart v-if="records.length && (trendMetric === 'tokens' || total.priced)" :option="trend" :label="`按服务堆叠的${trendMetric === 'tokens' ? 'Tokens' : '已定价费用'}趋势，${byHour ? '每小时' : '每日'}一柱`" :animations="state.settings.animations" />
      <div v-else class="empty-state chart-empty">{{ state.usage.scannedAt === null ? '尚未读取本机日志' : !records.length ? '此时间范围没有用量记录' : '此时间范围的记录尚未定价' }}</div>
    </section>
    <section class="surface table-surface" :class="{ 'overview-table': page === 'overview' }">
      <div class="section-heading">
        <template v-if="page === 'overview'">
          <div class="summary-table-heading">
            <h2 class="sr-only">用量汇总</h2>
            <SlidingSelection v-slot="{ highlight }" :selection="groupBy" class="segmented" role="group" aria-label="汇总分组">
              <component :is="highlight ? 'span' : 'label'" v-for="item in [{ value: 'model', label: '模型' }, { value: 'project', label: '项目' }, { value: 'session', label: '对话' }]" :key="item.value" class="segment-option" :data-selected="groupBy === item.value"><input v-if="!highlight" v-model="groupBy" class="sr-only" type="radio" name="overview-group" :value="item.value" />{{ item.label }}</component>
            </SlidingSelection>
            <span class="count">{{ state.usage.scannedAt === null ? '—' : `${groups.length} 项` }}</span>
          </div>
          <Button v-if="groupBy !== 'model'" variant="ghost" size="sm" @click="openInDetails(groupBy)">在明细中查看<ChevronRight :size="13" /></Button>
        </template>
        <template v-else>
          <SlidingSelection v-slot="{ highlight }" :selection="view" class="segmented" role="group" aria-label="明细分组">
            <component :is="highlight ? 'span' : 'label'" v-for="item in [{ value: 'record', label: '按记录' }, { value: 'session', label: '按对话' }, { value: 'project', label: '按项目' }]" :key="item.value" class="segment-option" :data-selected="view === item.value"><input v-if="!highlight" v-model="view" class="sr-only" type="radio" name="detail-view" :value="item.value" @change="search = ''" />{{ item.label }}</component>
          </SlidingSelection>
          <div class="record-actions"><label class="search-box"><Search :size="14" /><input v-model="search" :placeholder="view === 'record' ? '搜索对话、项目或模型' : view === 'session' ? '搜索对话或项目' : '搜索项目'" aria-label="搜索" /></label><DetailColumnsMenu v-if="recordView" :selected="state.settings.detailColumns" /></div>
        </template>
      </div>
      <UsageRecordTable v-if="recordView" :records="matchingRecords" :state="state" :reset-key="recordFilterKey" show-identity />
      <template v-else><div ref="tableScroll" class="table-scroll"><table class="usage-table" :class="{ 'project-table': grouping === 'project' }" :style="{ '--tokens-column-width': tokenColumnWidth }">
        <thead><tr>
          <th class="name-column">{{ grouping === 'session' ? '对话' : grouping === 'project' ? '项目' : '模型' }}</th>
          <th v-if="grouping !== 'model'" class="secondary-column" :class="{ 'time-column': grouping === 'session' }" :aria-sort="grouping === 'session' ? sortState('last') : undefined"><TableSortButton v-if="grouping === 'session'" label="最近用量" :active="sort === 'last'" :direction="direction" @click="selectSort('last')" /><template v-else>目录</template></th>
          <th class="number count-column" :aria-sort="sortState('count')"><TableSortButton label="记录数" :active="sort === 'count'" :direction="direction" @click="selectSort('count')" /></th>
          <th class="number tokens-column" :aria-sort="sortState('tokens')"><TableSortButton label="Tokens" :active="sort === 'tokens'" :direction="direction" @click="selectSort('tokens')" /></th>
          <th class="number cost-column" :aria-sort="sortState('cost')"><TableSortButton :label="costColumnLabel(summaryTotal)" :active="sort === 'cost'" :direction="direction" @click="selectSort('cost')" /></th>
          <th class="number share-column" :title="metric === 'tokens' ? 'Tokens 占比' : '费用占比'">{{ metric === 'tokens' ? 'Tokens 占比' : '费用占比' }}</th>
          <th class="number cache-column" :aria-sort="sortState('hitRate')"><TableSortButton label="缓存命中率" :active="sort === 'hitRate'" :direction="direction" @click="selectSort('hitRate')" /></th>
        </tr></thead>
        <tbody><tr v-for="group in pageRows" :key="group.key">
          <td><button class="table-link" :title="`${group.name}\n${group.key}`" @click="showDetail(group.name, group.records)"><span>{{ group.name }}<small v-if="grouping !== 'project'">{{ group.subtitle }}</small></span><ChevronRight :size="13" /></button></td>
          <td v-if="grouping !== 'model'" class="muted secondary-column"><span :title="grouping === 'session' ? dateText(group.last, true) : group.subtitle">{{ grouping === 'session' ? dateText(group.last) : group.subtitle }}</span></td>
          <td class="number" :title="group.total.count.toLocaleString()">{{ group.total.count.toLocaleString() }}</td>
          <td class="number">{{ group.total.tokens.toLocaleString('zh-CN') }}</td>
          <td class="number" :title="costTooltip(group.total)"><span :class="{ 'unpriced-text': group.total.count && !group.total.priced }">{{ summaryMoney(group.total) }}</span></td>
          <td class="number muted">{{ metricValue(summaryTotal, metric) ? percent(metricValue(group.total, metric) / metricValue(summaryTotal, metric)) : '—' }}</td>
          <td class="number muted">{{ percent(group.total.hitRate) }}</td>
        </tr></tbody>
      </table><div v-if="!groups.length" class="empty-state">{{ state.usage.scannedAt === null ? '尚未读取本机日志' : search ? '没有匹配的记录' : '此时间范围没有用量记录' }}</div></div>
      <TablePagination v-model:page="tablePage" v-model:page-size="pageSize" :total="groups.length" />
      </template>
    </section>
    <section v-if="page === 'overview'" class="surface heatmap-section"><div class="section-heading"><h2>每日用量</h2></div><Chart v-if="hasReadableUsage && records.length" :option="heatmap" label="当前时间范围内每日 Tokens 用量热力图" :height="150" :animations="false" /><div v-else class="empty-state">{{ hasReadableUsage ? '此时间范围没有用量记录' : '尚未读取本机日志' }}</div><p v-if="hasReadableUsage && records.length" class="heatmap-legend">低 <span class="heatmap-scale" /> 高</p></section>
    <UsageDetailDialog v-if="detail" :title="detail.title" :records="detail.records" :state="state" @close="detail = null" />
  </div>
</template>
