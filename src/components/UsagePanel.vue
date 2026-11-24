<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useMutationObserver } from '@vueuse/core'
import { groupBy as groupRecords } from '@pmun/utils'
import { ChevronLeft, ChevronRight, CircleHelp, Search } from '@lucide/vue'
import { TooltipProvider, TooltipRoot, TooltipTrigger, TooltipPortal, TooltipContent } from 'reka-ui'
import { format, type EChartsCoreOption } from 'echarts/core'
import type { CustomSeriesOption } from 'echarts/charts'
import type { AppSnapshot, Metric, Page, UsageRecord } from '@/types'
import { basename, compareSummaries, costCardTitle, costColumnLabel, costLabel, costTooltip, dateText, dateTimeKey, dayKey, metricShare, metricValue, money, percent, serviceName, shortTokens, shiftDay, startOfDay, summarize, summaryAmount, summaryMoney, type Summary } from '@/lib/usage'
import { chartReturn, openChartRecords, overviewGroupBy, overviewTrendMetric, parseUsageDateTime, syncOverviewToDetails, usageRanges, usageService, useUsageFilters, type UsageSort } from '@/lib/usage-filters'
import { compareTableNumbers, useTablePagination } from '@/lib/table'
import TablePagination from './TablePagination.vue'
import TableSortButton from './TableSortButton.vue'
import UsageRecordTable from './UsageRecordTable.vue'
import DetailColumnsMenu from './DetailColumnsMenu.vue'
import { Button } from '@/components/ui/button'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import Chart from './Chart.vue'
import AnimatedNumber from './AnimatedNumber.vue'
import UsageComparison from './UsageComparison.vue'
import SlidingSelection from './SlidingSelection.vue'
import UsageDetailDialog from './UsageDetailDialog.vue'
import antigravityIcon from '@/assets/antigravity.svg'

const props = defineProps<{ state: AppSnapshot; page: Page; clock: { now: number; calendar: string } }>()
const emit = defineEmits<{ navigate: [page: Page] }>()
const { view, period, metric, sort, direction, model, search, start, end } = useUsageFilters(() => props.page)
const groupBy = overviewGroupBy
const trendMetric = overviewTrendMetric
function readHeatmapColors() {
  const styles = getComputedStyle(document.documentElement)
  return { background: styles.getPropertyValue('--card').trim(), empty: styles.getPropertyValue('--secondary').trim() }
}
const heatmapColors = ref(readHeatmapColors())
useMutationObserver(document.documentElement, () => { heatmapColors.value = readHeatmapColors() }, { attributes: true, attributeFilter: ['class'] })
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
  // Ranges are end-exclusive. Include records timestamped at the current millisecond.
  const cutoff = period.value === 'today' ? (Math.floor(props.clock.now * 1000) + 1) / 1000 : props.clock.now + 1
  return { from: from.getTime() / 1000, to: Math.min(to.getTime() / 1000, cutoff), days }
})
const rangeText = computed(() => {
  if (period.value === 'all') return ''
  if (period.value === 'custom') return customRange.value ? `${dateTimeKey(new Date(range.value.from * 1000), true).replace('T', ' ')} — ${dateTimeKey(new Date(range.value.to * 1000), true).replace('T', ' ')}` : ''
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
const tokenBreakdown = computed(() => [
  { label: '新增输入', value: total.value.input, known: total.value.inputKnown },
  { label: '输出', value: total.value.output, known: total.value.outputKnown },
  { label: '缓存命中', value: total.value.cached, known: total.value.cachedKnown },
  { label: '缓存写入', value: total.value.cacheWrite, known: total.value.cacheWriteKnown },
].map(({ label, value, known }) => ({ label, value: hasReadableUsage.value && (known || value > 0) ? value : null })))
const previous = computed(() => {
  if (period.value === 'all' || range.value.to <= range.value.from) return null
  const duration = period.value === 'custom' ? customRange.value!.to - customRange.value!.from : 86400
  const from = range.value.days ? shiftDay(new Date(range.value.from * 1000), -range.value.days).getTime() / 1000 : range.value.from - duration
  const to = range.value.days ? shiftDay(new Date(range.value.to * 1000), -range.value.days).getTime() / 1000 : range.value.to - duration
  return { from, to, total: summarize(availableRecords.value.filter(record => record.date >= from && record.date < to && inModel(record))) }
})
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
    models: model.value === 'all' ? Object.values(groupRecords(records, record => `${record.service}:${record.model}`)).map(items => ({
      name: items[0]!.model, service: items[0]!.service, total: summarize(items),
    })) : [],
    codex: summarize(records.filter(record => record.service === 'codex')),
    antigravity: summarize(records.filter(record => record.service === 'antigravity')),
  }))
})
const rankedModels = computed(() => {
  const servicesByModel = new Map<string, Set<string>>()
  for (const bucket of buckets.value) {
    for (const { name, service } of bucket.models) {
      const owners = servicesByModel.get(name) ?? new Set<string>()
      owners.add(service)
      servicesByModel.set(name, owners)
    }
  }
  return buckets.value.map(bucket => bucket.models
    .filter(item => trendMetric.value === 'tokens' || item.total.priced)
    .sort((a, b) => compareSummaries(a.total, b.total, trendMetric.value) || a.name.localeCompare(b.name))
    .slice(0, 3)
    .map(item => {
      const name = item.name === 'unknown' ? '未知模型' : item.name
      return { ...item, name: servicesByModel.get(item.name)!.size > 1 ? `${name} · ${serviceName(item.service)}` : name }
    }))
})
function trendTooltip(params: { dataIndex: number } | { dataIndex: number }[]) {
  const index = Array.isArray(params) ? params[0]?.dataIndex : params.dataIndex
  if (index === undefined) return ''
  const bucket = buckets.value[index]!
  const date = byHour.value ? dateTimeKey(new Date(Number(bucket.key) * 1000)).replace('T', ' ') : bucket.key
  const metric = trendMetric.value
  const value = (summary: Summary, kind: Metric) => kind === 'tokens' ? `${summary.tokens.toLocaleString('zh-CN')} Tokens` : summaryMoney(summary)
  const totalsRow = (name: string, summary: Summary) => `<span>${name}</span><b>${value(summary, metric)}</b><span>${value(summary, metric === 'tokens' ? 'cost' : 'tokens')}</span>`
  const services = selectedServices.value
  const heading = totalsRow(services.length === 1 ? services[0]!.name : '合计', bucket.total)
  const breakdown = services.length === 1 ? '' : services.map(service => totalsRow(service.name, bucket[service.id])).join('')
  const models = rankedModels.value[index]!.map(item => `<span>${format.encodeHTML(item.name)}</span><b>${value(item.total, metric)}</b><span>${percent(metricShare(item.total, bucket.total, metric))}</span>`).join('')
  const coverage = bucket.total.priced && bucket.total.unpriced ? ` · ${bucket.total.unpriced} 条未定价` : ''
  return `<div class="trend-tip"><div class="trend-tip-date">${date}${coverage}</div><div class="trend-tip-grid trend-tip-totals">${heading}${breakdown}</div>`
    + (models ? `<div class="trend-tip-grid trend-tip-models">${models}</div>` : '') + '</div>'
}

// Use the elapsed part of each hour for both its bar and its hover area.
function todayTrend() {
  const hours = buckets.value.length
  const elapsed = (props.clock.now - range.value.from) / 3600
  const observed = buckets.value.filter(bucket => Number(bucket.key) <= props.clock.now)
  const spans = observed.map((_, index) => [index, Math.min(index + 1, elapsed)] as const)
  const series = selectedServices.value.map((service, serviceIndex): CustomSeriesOption => ({
    name: service.name, type: 'custom', itemStyle: { color: service.color }, encode: { x: [0, 1], y: [2, 3] },
    data: observed.map((bucket, index) => {
      const base = serviceIndex === 0 ? 0 : metricValue(bucket.codex, trendMetric.value)
      return [...spans[index]!, base, base + metricValue(bucket[service.id], trendMetric.value)]
    }),
    renderItem: (_, api) => {
      const [left, bottom] = api.coord([api.value(0), api.value(2)])
      const [right, top] = api.coord([api.value(1), api.value(3)])
      if (bottom === top) return
      const width = Math.min(30, (right! - left!) * 0.7)
      return { type: 'rect', shape: { x: (left! + right! - width) / 2, y: top!, width, height: bottom! - top! }, style: { fill: service.color } }
    },
    ...(serviceIndex === 0 && {
      markArea: { label: { show: false }, emphasis: { disabled: true }, itemStyle: { color: 'transparent' }, data: spans.map(([start, end]) => [{ xAxis: start }, { xAxis: end }]) },
      markLine: { silent: true, symbol: 'none', precision: -1, label: { formatter: '现在', position: 'end', fontSize: 11 }, lineStyle: { color: '#888', width: 1, opacity: 0.65, type: 'solid' }, data: [{ xAxis: elapsed }] },
    }),
  }))
  return {
    xAxis: { type: 'value', min: 0, max: hours, interval: 1, axisTick: { show: false }, axisLine: { show: false }, splitLine: { show: false }, axisLabel: { hideOverlap: true, formatter: (hour: number) => hour === hours ? '24:00' : dateTimeKey(new Date((range.value.from + hour * 3600) * 1000)).slice(11) } },
    series,
  }
}
const trend = computed<EChartsCoreOption>(() => ({
  grid: { left: 54, right: 20, top: period.value === 'today' ? 40 : 30, bottom: 35 },
  legend: { top: 0, selectedMode: false, icon: 'roundRect' },
  tooltip: { trigger: period.value === 'today' ? 'item' : 'axis', renderMode: 'html', appendTo: 'body', transitionDuration: 0, hideDelay: 0, formatter: trendTooltip },
  yAxis: { type: 'value', name: trendMetric.value === 'tokens' ? 'Tokens' : `${costLabel(total.value)} ($)`, min: 0, splitNumber: 3, axisLabel: { formatter: (value: number) => trendMetric.value === 'tokens' ? shortTokens(value) : money(String(value)) }, splitLine: { lineStyle: { color: '#88888820' } } },
  ...(period.value === 'today' ? todayTrend() : {
    xAxis: { type: 'category', data: buckets.value.map(bucket => bucket.key), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { hideOverlap: true, formatter: (value: string) => byHour.value ? dateTimeKey(new Date(Number(value) * 1000)).slice(hourlyAcrossDays.value ? 5 : 11).replace('T', ' ').replace('-', '/') : value.slice(5).replace('-', '/') } },
    series: selectedServices.value.map(service => ({
      name: service.name, type: 'bar', stack: 'usage', barMaxWidth: 30, itemStyle: { color: service.color },
      data: buckets.value.map(bucket => {
        const summary = bucket[service.id]
        return trendMetric.value === 'cost' && summary.count && !summary.priced ? null : metricValue(summary, trendMetric.value)
      }),
    })),
  }),
}))
const showTrend = computed(() => hasReadableUsage.value && (
  total.value.count ? trendMetric.value === 'tokens' || total.value.priced > 0 : period.value === 'today'
))
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
const currentCost = computed(() => hasReadableUsage.value ? summaryAmount(summaryTotal.value) : null)
const previousCost = computed(() => previous.value ? summaryAmount(previous.value.total) : null)
const summaryRows = computed(() => pageRows.value.map(group => ({
  ...group, share: metricShare(group.total, summaryTotal.value, metric.value),
})))
const tokenColumnWidth = computed(() => `calc(${groups.value.reduce((width, group) => Math.max(width, group.total.tokens.toLocaleString('zh-CN').length), 14)}ch + 26px)`)
const heatmapDays = computed(() => {
  const earliest = period.value === 'all' ? records.value.reduce((date, record) => Math.min(date, record.date), range.value.to) : range.value.from
  const days = groupRecords(records.value, record => dayKey(new Date(record.date * 1000)))
  for (let day = startOfDay(new Date(earliest * 1000)); day.getTime() / 1000 < range.value.to; day = shiftDay(day, 1)) days[dayKey(day)] ??= []
  return Object.entries(days).sort(([a], [b]) => a.localeCompare(b)).map(([day, records]) => {
    const summary = summarize(records)
    return { value: [day, summary.tokens] as [string, number], summary }
  })
})
const heatmap = computed<EChartsCoreOption>(() => {
  const last = startOfDay(new Date((range.value.to - 0.001) * 1000))
  const earliest = heatmapDays.value[0]?.value[0] ?? dayKey(last)
  const first = new Date(Math.min(new Date(`${earliest}T00:00:00`).getTime(), shiftDay(last, -370).getTime()))
  const data = heatmapDays.value
  return {
    tooltip: { renderMode: 'html', appendTo: 'body', formatter: (params: { dataIndex: number }) => {
      const day = data[params.dataIndex]!, summary = day.summary
      return `${day.value[0]}<br>${summary.tokens.toLocaleString('zh-CN')} Tokens<br>${costLabel(summary)}：${summaryMoney(summary)}`
    } },
    visualMap: { show: false, min: 0, max: Math.max(1, ...data.map(item => item.summary.tokens)), inRange: { color: [heatmapColors.value.empty, '#a3d1ca', '#679e94', '#33786c'] } },
    calendar: {
      top: 28, left: 32, right: 8, bottom: 4, range: [dayKey(first), dayKey(last)], cellSize: ['auto', 15],
      splitLine: { show: false }, itemStyle: { color: heatmapColors.value.empty, borderWidth: 2, borderColor: heatmapColors.value.background }, yearLabel: { show: false },
      dayLabel: { firstDay: 1, nameMap: 'ZH', fontSize: 10, color: '#888' }, monthLabel: { nameMap: 'ZH', color: '#888', fontSize: 11 },
    },
    series: [{ type: 'heatmap', coordinateSystem: 'calendar', data }],
  }
})
function showDetail(name: string, items: UsageRecord[]) { detail.value = { title: name, records: items } }
function openInDetails(targetView: 'session' | 'project') { syncOverviewToDetails(targetView); emit('navigate', 'details') }
function openTimeRecords(from: number, to: number) {
  const start = Math.max(from, range.value.from), end = Math.min(to, range.value.to)
  if (start >= end) return
  openChartRecords(start, end)
  emit('navigate', 'details')
}
function openTrendRecords(index: number) {
  const bucket = buckets.value[index]
  if (!bucket) return
  const from = byHour.value ? new Date(Number(bucket.key) * 1000) : new Date(`${bucket.key}T00:00:00`)
  openTimeRecords(from.getTime() / 1000, byHour.value ? from.getTime() / 1000 + 3600 : shiftDay(from, 1).getTime() / 1000)
}
function openHeatmapRecords(index: number) {
  const day = heatmapDays.value[index]
  if (!day) return
  const from = new Date(`${day.value[0]}T00:00:00`)
  openTimeRecords(from.getTime() / 1000, shiftDay(from, 1).getTime() / 1000)
}
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
        <div class="date-range"><label>开始 <input v-model="start" type="datetime-local" step="any" :max="end" required :aria-invalid="!customRange" :aria-describedby="!customRange ? 'usage-range-error' : undefined" /></label><span>—</span><label>结束 <input v-model="end" type="datetime-local" step="any" :min="start" required :aria-invalid="!customRange" :aria-describedby="!customRange ? 'usage-range-error' : undefined" /></label></div>
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
        <Button v-if="page === 'details' && chartReturn" variant="ghost" size="sm" @click="emit('navigate', 'overview')"><ChevronLeft :size="13" />返回图表</Button>
      </div>
    </div>
    <div v-if="page === 'overview'" class="summary-cards">
      <div class="summary-card tokens-card">
        <div class="summary-reading">
          <span class="metric-label">总 Tokens</span>
          <strong class="card-value" :title="hasReadableUsage ? undefined : '尚未读取本机日志'"><AnimatedNumber :value="hasReadableUsage ? summaryTotal.tokens : null" /></strong>
          <UsageComparison v-if="hasReadableUsage && previous" kind="tokens" :current="summaryTotal.tokens" :previous="previous.total.tokens" :title="`上期：${previous.total.tokens.toLocaleString('zh-CN')} Tokens`" />
        </div>
        <dl class="summary-footer summary-counts">
          <div v-for="item in tokenBreakdown" :key="item.label">
            <dt>{{ item.label }}</dt>
            <dd :title="item.value?.toLocaleString('zh-CN')"><AnimatedNumber :value="item.value" kind="tokens" /></dd>
          </div>
        </dl>
      </div>
      <div class="summary-card" :title="costCardTitle(summaryTotal)">
        <div class="summary-reading">
          <span class="metric-label">{{ costLabel(summaryTotal) }}</span>
          <strong class="card-value" :class="{ 'unpriced-text': hasReadableUsage && summaryTotal.count && !summaryTotal.priced }"><AnimatedNumber :value="currentCost" kind="money" :empty="hasReadableUsage ? '未定价' : '—'" /></strong>
          <UsageComparison v-if="currentCost !== null && previousCost !== null && previous" kind="money" :current="currentCost" :previous="previousCost" :title="`上期：${costTooltip(previous.total)}`" />
        </div>
        <div class="summary-footer cost-notes">
          <span>API 等价估算</span>
          <span v-if="hasReadableUsage && previous">上期 {{ dateText(previous.from) }} — {{ dateText(previous.to - (range.days ? 1 : 0)) }}</span>
        </div>
      </div>
      <div class="summary-card">
        <div class="summary-reading">
          <span class="metric-label" title="缓存命中 ÷ 全部输入">缓存命中率</span>
          <strong class="card-value"><AnimatedNumber :value="hasReadableUsage ? summaryTotal.hitRate : null" kind="rate" /></strong>
          <div v-if="hasReadableUsage && summaryTotal.hitRate !== null" class="quota-track hit-rate-track" aria-hidden="true"><div :style="{ width: `${summaryTotal.hitRate * 100}%` }" /></div>
        </div>
        <dl class="summary-footer summary-counts">
          <div><dt>对话数</dt><dd><AnimatedNumber :value="hasReadableUsage ? summaryTotal.sessions : null" /></dd></div>
          <div><dt>记录数</dt><dd><AnimatedNumber :value="hasReadableUsage ? summaryTotal.count : null" /></dd></div>
        </dl>
      </div>
    </div>
    <div v-else class="surface summary-bar">
      <div class="summary-bar-item"><span class="metric-label">总 Tokens</span><strong><AnimatedNumber :value="hasReadableUsage ? summaryTotal.tokens : null" /></strong></div>
      <div class="summary-bar-item" :title="costCardTitle(summaryTotal)"><span class="metric-label">{{ costLabel(summaryTotal) }}</span><strong :class="{ 'unpriced-text': state.usage.scannedAt && summaryTotal.count && !summaryTotal.priced }"><AnimatedNumber :value="currentCost" kind="money" :empty="hasReadableUsage ? '未定价' : '—'" /></strong><small class="metric-note">API 等价估算</small></div>
      <div class="summary-bar-item"><span class="metric-label">对话数</span><strong><AnimatedNumber :value="hasReadableUsage ? summaryTotal.sessions : null" /></strong></div>
      <div class="summary-bar-item" title="缓存命中 ÷ 全部输入"><span class="metric-label">缓存命中率</span><strong><AnimatedNumber :value="hasReadableUsage ? summaryTotal.hitRate : null" kind="rate" /></strong></div>
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
      <Chart v-if="showTrend" :option="trend" :label="`按服务堆叠的${trendMetric === 'tokens' ? 'Tokens' : '已定价费用'}趋势，${byHour ? '每小时' : '每日'}一柱，点击查看该时段记录`" :animations="state.settings.animations" @select="openTrendRecords" />
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
            <span class="count"><AnimatedNumber :value="hasReadableUsage ? groups.length : null" suffix=" 项" /></span>
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
        <tbody><tr v-for="group in summaryRows" :key="group.key">
          <td><button class="table-link" :title="`${group.name}\n${group.key}`" @click="showDetail(group.name, group.records)"><span>{{ group.name }}<small v-if="grouping !== 'project'">{{ group.subtitle }}</small></span><ChevronRight :size="13" /></button></td>
          <td v-if="grouping !== 'model'" class="muted secondary-column"><span :title="grouping === 'session' ? dateText(group.last, true) : group.subtitle">{{ grouping === 'session' ? dateText(group.last) : group.subtitle }}</span></td>
          <td class="number" :title="group.total.count.toLocaleString()"><AnimatedNumber :value="group.total.count" /></td>
          <td class="number"><AnimatedNumber :value="group.total.tokens" /></td>
          <td class="number" :title="costTooltip(group.total)"><span :class="{ 'unpriced-text': group.total.count && !group.total.priced }"><AnimatedNumber :value="summaryAmount(group.total)" kind="money" empty="未定价" /></span></td>
          <td class="number muted"><div class="usage-share"><span v-if="group.share !== null" class="usage-share-track" aria-hidden="true"><span :style="{ width: `${group.share * 100}%` }" /></span><span><AnimatedNumber :value="group.share" kind="rate" /></span></div></td>
          <td class="number muted"><AnimatedNumber :value="group.total.hitRate" kind="rate" /></td>
        </tr></tbody>
      </table><div v-if="!groups.length" class="empty-state">{{ state.usage.scannedAt === null ? '尚未读取本机日志' : search ? '没有匹配的记录' : '此时间范围没有用量记录' }}</div></div>
      <TablePagination v-model:page="tablePage" v-model:page-size="pageSize" :total="groups.length" />
      </template>
    </section>
    <section v-if="page === 'overview'" class="surface heatmap-section">
      <div class="section-heading"><h2>每日用量</h2></div>
      <Chart v-if="hasReadableUsage && heatmapDays.length" :option="heatmap" label="当前时间范围内每日 Tokens 用量热力图，点击日期查看当天记录" :height="150" :animations="false" @select="openHeatmapRecords" />
      <div v-else class="empty-state">{{ hasReadableUsage ? '此时间范围没有用量记录' : '尚未读取本机日志' }}</div>
      <p v-if="hasReadableUsage && heatmapDays.length" class="heatmap-legend">低 <span class="heatmap-scale" /> 高</p>
    </section>
    <UsageDetailDialog v-if="detail" :title="detail.title" :records="detail.records" :state="state" @close="detail = null" />
  </div>
</template>
