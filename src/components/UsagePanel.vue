<script setup lang="ts">
import { computed, ref } from 'vue'
import { ArrowDown, ChevronRight, Info, Search } from '@lucide/vue'
import type { EChartsCoreOption } from 'echarts/core'
import type { AppSnapshot, Metric, Page, UsageRecord } from '@/types'
import { basename, costLabel, costTooltip, dateText, dayKey, metricValue, money, percent, shortTokens, shiftDay, startOfDay, summarize, summaryMoney } from '@/lib/usage'
import { Button } from '@/components/ui/button'
import Chart from './Chart.vue'
import SlidingSelection from './SlidingSelection.vue'
import UsageDetailDialog from './UsageDetailDialog.vue'

const props = defineProps<{ state: AppSnapshot; page: Page; clock: { now: number; calendar: string } }>()
const period = ref('7')
const metric = ref<Metric>('tokens')
const heatMetric = ref<Metric>('tokens')
const groupBy = ref('model')
const model = ref('all')
const search = ref('')
const start = ref(dayKey(shiftDay(new Date(), -6)))
const end = ref(dayKey(new Date()))
const detail = ref<{ title: string; records: UsageRecord[] } | null>(null)
const limit = ref(100)
const ranges = [{ value: 'today', label: '今天' }, { value: 'yesterday', label: '昨天' }, { value: '7', label: '7 天' }, { value: '30', label: '30 天' }, { value: 'all', label: '全部' }, { value: 'custom', label: '自定义' }]
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
const availableRecords = computed(() => props.state.usage.records.filter(record => record.service === 'codex' && record.date <= props.clock.now))
const models = computed(() => [...new Set(availableRecords.value.map(record => record.model))].sort())
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
  if (!before) return current ? '新增' : '持平'
  const difference = (current - before) / before
  return `${difference > 0 ? '+' : ''}${(difference * 100).toFixed(1)}%`
}
const byHour = computed(() => period.value === 'today' || period.value === 'yesterday')
const buckets = computed(() => {
  const values = new Map<string, UsageRecord[]>()
  for (const record of records.value) {
    const date = new Date(record.date * 1000)
    const key = byHour.value ? `${String(date.getHours()).padStart(2, '0')}:00` : dayKey(date)
    const bucket = values.get(key) ?? []; bucket.push(record); values.set(key, bucket)
  }
  if (byHour.value) for (let hour = 0; hour < 24; hour++) { const key = `${String(hour).padStart(2, '0')}:00`; if (!values.has(key)) values.set(key, []) }
  else if (period.value !== 'all' && range.value.days <= 366) for (let day = new Date(range.value.from * 1000); day.getTime() / 1000 < range.value.to; day = shiftDay(day, 1)) if (!values.has(dayKey(day))) values.set(dayKey(day), [])
  return [...values].sort(([a], [b]) => a.localeCompare(b)).map(([key, records]) => ({ key, total: summarize(records) }))
})
const trend = computed<EChartsCoreOption>(() => ({
  grid: { left: 54, right: 16, top: 20, bottom: 35 },
  tooltip: { trigger: 'axis', renderMode: 'richText', valueFormatter: (value: number) => metric.value === 'tokens' ? value.toLocaleString('zh-CN') : money(String(value)) },
  xAxis: { type: 'category', data: buckets.value.map(bucket => bucket.key), axisTick: { show: false }, axisLine: { show: false }, axisLabel: { hideOverlap: true, formatter: (value: string) => byHour.value ? value : value.slice(5).replace('-', '/') } },
  yAxis: { type: 'value', splitNumber: 3, axisLabel: { formatter: (value: number) => metric.value === 'tokens' ? shortTokens(value) : `$${value}` }, splitLine: { lineStyle: { color: '#88888820' } } },
  series: [{ name: metric.value === 'tokens' ? 'Tokens' : costLabel(total.value), type: 'bar', barMaxWidth: 30, itemStyle: { borderRadius: [3, 3, 0, 0] }, data: buckets.value.map(bucket => metric.value === 'cost' && bucket.total.count && !bucket.total.priced ? null : metricValue(bucket.total, metric.value)) }],
}))
function grouped(kind: string) {
  const values = new Map<string, UsageRecord[]>()
  for (const record of records.value) {
    const key = kind === 'session' ? record.session : kind === 'project' ? props.state.usage.projectRoots[record.project] ?? record.project : record.model
    const bucket = values.get(key) ?? []; bucket.push(record); values.set(key, bucket)
  }
  return [...values].map(([key, records]) => {
    const project = props.state.usage.projectRoots[records[0]!.project] ?? records[0]!.project
    return { key, records, total: summarize(records), name: kind === 'session' ? basename(project) : kind === 'project' ? basename(key) : key, subtitle: kind === 'session' ? key.slice(0, 12) : kind === 'project' ? key : '', last: records.reduce((latest, record) => Math.max(latest, record.date), 0) }
  }).sort((a, b) => metricValue(b.total, metric.value) - metricValue(a.total, metric.value))
}
const groups = computed(() => grouped(props.page === 'sessions' ? 'session' : props.page === 'projects' ? 'project' : groupBy.value).filter(group => props.page === 'overview' || !search.value || `${group.name} ${group.key}`.toLowerCase().includes(search.value.toLowerCase())))
const topSessions = computed(() => grouped('session').slice(0, 5))
const heatmap = computed<EChartsCoreOption>(() => {
  const last = startOfDay(new Date(props.clock.now * 1000)), first = shiftDay(last, -370)
  const days = new Map<string, UsageRecord[]>()
  for (const record of availableRecords.value) { const key = dayKey(new Date(record.date * 1000)); const bucket = days.get(key) ?? []; bucket.push(record); days.set(key, bucket) }
  const data = []
  for (let day = first; day <= last; day = shiftDay(day, 1)) {
    const summary = summarize(days.get(dayKey(day)) ?? [])
    data.push({ value: [dayKey(day), metricValue(summary, heatMetric.value)], priced: summary.priced, unpriced: summary.unpriced, count: summary.count, itemStyle: summary.unpriced && heatMetric.value === 'cost' ? { borderType: 'dashed', borderColor: '#ab743e', borderWidth: 1 } : undefined })
  }
  return {
    tooltip: { renderMode: 'richText', formatter: (params: { value: [string, number]; data: { priced: number; unpriced: number; count: number } }) => `${params.value[0]}\n${heatMetric.value === 'tokens' ? `${params.value[1].toLocaleString()} Tokens` : params.data.count && !params.data.priced ? '未定价' : money(String(params.value[1]))}${heatMetric.value === 'cost' && params.data.unpriced ? `\n${params.data.unpriced} 条未定价` : ''}` },
    visualMap: { show: false, min: 0, max: Math.max(1, ...data.map(item => Number(item.value[1]))), inRange: { color: ['#88888815', '#a3d1ca', '#679e94', '#33786c'] } },
    calendar: { top: 28, left: 32, right: 8, bottom: 4, range: [dayKey(first), dayKey(last)], cellSize: ['auto', 15], splitLine: { show: false }, itemStyle: { borderWidth: 2, borderColor: 'transparent' }, yearLabel: { show: false }, dayLabel: { firstDay: 1, nameMap: 'ZH', fontSize: 10, color: '#888' }, monthLabel: { nameMap: 'ZH', color: '#888', fontSize: 11 } },
    series: [{ type: 'heatmap', coordinateSystem: 'calendar', data }],
  }
})
function showDetail(name: string, items: UsageRecord[]) { detail.value = { title: name, records: [...items].sort((a, b) => b.date - a.date) } }
</script>

<template>
  <div class="usage-page" :class="{ 'table-page': page !== 'overview' }">
    <div class="usage-filters">
      <div class="filter-bar">
        <SlidingSelection v-slot="{ highlight }" :selection="period" class="segmented" role="group" aria-label="日期范围">
          <component :is="highlight ? 'span' : 'label'" v-for="item in ranges" :key="item.value" class="segment-option" :data-selected="period === item.value"><input v-if="!highlight" v-model="period" class="sr-only" type="radio" name="date-range" :value="item.value" @change="limit = 100" />{{ item.label }}</component>
        </SlidingSelection>
        <div class="filter-spacer" />
        <label class="sr-only" for="model-filter">模型</label>
        <select id="model-filter" v-model="model" class="native-select"><option value="all">全部模型</option><option v-for="item in models" :key="item">{{ item }}</option></select>
        <SlidingSelection v-slot="{ highlight }" :selection="metric" class="segmented" role="group" aria-label="统计指标"><component :is="highlight ? 'span' : 'label'" class="segment-option" :data-selected="metric === 'tokens'"><input v-if="!highlight" v-model="metric" class="sr-only" type="radio" name="usage-metric" value="tokens" />Tokens</component><component :is="highlight ? 'span' : 'label'" class="segment-option" :data-selected="metric === 'cost'"><input v-if="!highlight" v-model="metric" class="sr-only" type="radio" name="usage-metric" value="cost" />费用</component></SlidingSelection>
      </div>
      <div v-if="period === 'custom'" class="date-range"><label>开始 <input v-model="start" type="date" :max="end" /></label><span>—</span><label>结束 <input v-model="end" type="date" :min="start" :max="dayKey(new Date())" /></label></div>
      <div class="source-line"><span :title="state.usage.source">本机日志<span v-if="period === 'custom'"> · {{ start }} — {{ end }}</span><span class="info-hint" aria-label="统计范围说明" title="包含本机已采集历史，可能来自多个账号；不代表当前账号或其他设备的全部用量。"><Info :size="12" /></span></span><span v-if="state.usage.scannedAt">扫描于 {{ dateText(state.usage.scannedAt) }}</span></div>
    </div>
    <div v-for="warning in state.usage.warnings" :key="warning" class="notice warning" role="status">{{ warning }}</div>
    <div class="usage-summary">
      <div class="summary-strip" :class="{ compact: page !== 'overview' }">
        <div><span class="metric-label">总 Tokens</span><strong :title="state.usage.scannedAt === null ? '尚未读取本机日志' : total.tokens.toLocaleString()">{{ state.usage.scannedAt ? shortTokens(total.tokens) : '—' }}</strong><span v-if="page === 'overview' && changeText('tokens')" class="comparison">{{ changeText('tokens') }} <span>较上期</span></span></div>
        <div :title="`API 等价估算，非订阅账单。${total.unpriced} 条记录未定价。`"><span class="metric-label">{{ costLabel(total) }}</span><strong>{{ state.usage.scannedAt ? summaryMoney(total) : '—' }}</strong><span v-if="page === 'overview' && changeText('cost')" class="comparison">{{ changeText('cost') }} <span>较上期</span></span></div>
      </div>
      <div class="summary-details"><span>{{ state.usage.scannedAt ? total.sessions.toLocaleString() : '—' }} 个对话</span><span title="缓存命中 ÷ 全部输入">缓存命中率 {{ state.usage.scannedAt ? percent(total.hitRate) : '—' }}</span><span v-if="page === 'overview' && state.usage.scannedAt !== null && previous" class="comparison-range">上期 {{ dateText(previous.from) }} — {{ dateText(previous.to - 1) }}</span></div>
    </div>
    <template v-if="page === 'overview'">
      <section class="surface chart-section"><div class="section-heading"><h2>用量趋势</h2><span>{{ metric === 'tokens' ? 'Tokens' : costLabel(total) }}</span></div><Chart v-if="records.length" :option="trend" :label="`当前期间${metric === 'tokens' ? 'Token' : '费用'}趋势`" :animations="state.settings.animations" /><div v-else class="empty-state chart-empty">{{ state.usage.scannedAt ? '此时间范围没有用量记录' : '尚未读取本机日志' }}</div></section>
      <div class="analysis-grid">
        <section class="surface"><div class="section-heading"><h2>用量构成</h2></div><div v-if="state.usage.scannedAt !== null" class="composition">
          <div v-for="item in [{ label: '新增输入', value: total.input }, { label: '输出', value: total.output }, { label: '缓存命中', value: total.cached }, { label: '缓存写入', value: total.cacheWrite }]" :key="item.label" class="composition-row"><span>{{ item.label }}</span><div class="composition-track"><div :style="{ width: `${total.tokens ? item.value / total.tokens * 100 : 0}%` }" /></div><strong :title="item.value.toLocaleString()">{{ shortTokens(item.value) }}</strong></div>
        </div><div v-else class="empty-state">尚未读取本机日志</div></section>
        <section class="surface"><div class="section-heading"><h2>高消耗对话</h2><span>{{ metric === 'tokens' ? 'Tokens' : costLabel(total) }}</span></div><div v-if="!topSessions.length" class="empty-state">{{ state.usage.scannedAt === null ? '尚未读取本机日志' : '暂无记录' }}</div><button v-for="group in topSessions" :key="group.key" class="ranking-row" @click="showDetail(group.name, group.records)"><span :title="group.key">{{ group.name }}<small>{{ dateText(group.last) }} · {{ group.subtitle }}</small></span><strong :title="metric === 'tokens' ? group.total.tokens.toLocaleString() : costTooltip(group.total)">{{ metric === 'tokens' ? shortTokens(group.total.tokens) : summaryMoney(group.total) }}</strong><ChevronRight :size="14" /></button></section>
      </div>
    </template>
    <section class="surface table-surface" :class="{ 'overview-table': page === 'overview' }">
      <div class="section-heading"><h2>{{ page === 'sessions' ? '对话明细' : page === 'projects' || groupBy === 'project' ? '项目汇总' : '模型汇总' }} <span class="count">{{ state.usage.scannedAt === null ? '—' : groups.length }}</span></h2><select v-if="page === 'overview'" v-model="groupBy" class="native-select small" aria-label="汇总分组" @change="limit = 100"><option value="model">按模型</option><option value="project">按项目</option></select><label v-else class="search-box"><Search :size="14" /><input v-model="search" :placeholder="page === 'sessions' ? '搜索对话或项目' : '搜索项目'" aria-label="搜索" /></label></div>
      <div class="table-scroll"><table><thead><tr><th>{{ page === 'sessions' ? '对话' : page === 'projects' || groupBy === 'project' ? '项目' : '模型' }}</th><th v-if="page !== 'overview' || groupBy === 'project'" class="secondary-column">{{ page === 'sessions' ? '最近用量' : '目录' }}</th><th class="number">记录数</th><th class="number">Tokens <ArrowDown v-if="metric === 'tokens'" :size="11" /></th><th class="number">{{ costLabel(total) }} <ArrowDown v-if="metric === 'cost'" :size="11" /></th><th class="number">占比</th><th class="number">缓存命中率</th></tr></thead><tbody><tr v-for="group in groups.slice(0, limit)" :key="group.key"><td><button class="table-link" :title="group.key" @click="showDetail(group.name, group.records)"><span>{{ group.name }}<small v-if="page === 'sessions'">{{ group.subtitle }}</small></span><ChevronRight :size="13" /></button></td><td v-if="page !== 'overview' || groupBy === 'project'" class="muted secondary-column"><span :title="page === 'sessions' ? dateText(group.last, true) : group.subtitle">{{ page === 'sessions' ? dateText(group.last) : group.subtitle }}</span></td><td class="number">{{ group.total.count }}</td><td class="number" :title="group.total.tokens.toLocaleString()">{{ shortTokens(group.total.tokens) }}</td><td class="number" :title="costTooltip(group.total)">{{ summaryMoney(group.total) }}</td><td class="number muted">{{ metric === 'cost' && total.unpriced ? '—' : metricValue(total, metric) ? percent(metricValue(group.total, metric) / metricValue(total, metric)) : '—' }}</td><td class="number muted">{{ percent(group.total.hitRate) }}</td></tr></tbody></table><div v-if="!groups.length" class="empty-state">{{ state.usage.scannedAt === null ? '尚未读取本机日志' : search ? '没有匹配的记录' : '此时间范围没有用量记录' }}</div><Button v-if="groups.length > limit" class="load-more" variant="outline" size="sm" @click="limit += 100">显示更多</Button></div>
    </section>
    <section v-if="page === 'overview'" class="surface heatmap-section"><div class="section-heading"><h2>最近 53 周</h2><SlidingSelection v-slot="{ highlight }" :selection="heatMetric" class="segmented small" role="group" aria-label="热力图指标"><component :is="highlight ? 'span' : 'label'" class="segment-option" :data-selected="heatMetric === 'tokens'"><input v-if="!highlight" v-model="heatMetric" class="sr-only" type="radio" name="heatmap-metric" value="tokens" />Tokens</component><component :is="highlight ? 'span' : 'label'" class="segment-option" :data-selected="heatMetric === 'cost'"><input v-if="!highlight" v-model="heatMetric" class="sr-only" type="radio" name="heatmap-metric" value="cost" />费用</component></SlidingSelection></div><Chart v-if="state.usage.scannedAt !== null" :option="heatmap" label="最近53周每日用量热力图" :height="150" :animations="false" /><div v-else class="empty-state">尚未读取本机日志</div><p v-if="state.usage.scannedAt !== null" class="heatmap-legend">低 <span class="heatmap-scale" /> 高<span v-if="heatMetric === 'cost'"> · 虚线表示含未定价记录</span></p></section>
    <UsageDetailDialog v-if="detail" :title="detail.title" :records="detail.records" :state="state" @close="detail = null" />
  </div>
</template>
