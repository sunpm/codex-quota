<script setup lang="ts">
import { computed, ref } from 'vue'
import { RefreshCw } from '@lucide/vue'
import type { EChartsCoreOption } from 'echarts/core'
import type { AppSnapshot, ChartTimeHover, QuotaSeries } from '@/types'
import { countdown, dateText, quotaLabel } from '@/lib/usage'
import { execute } from '@/lib/app'
import { Button } from '@/components/ui/button'
import Chart from './Chart.vue'
import AntigravityPanel from './AntigravityPanel.vue'
import AnnouncementPanel from './AnnouncementPanel.vue'
import SlidingSelection from './SlidingSelection.vue'

const props = defineProps<{ state: AppSnapshot; now: number }>()
const refreshPending = ref(false)
const refreshing = computed(() => refreshPending.value || props.state.quota.refreshing)
async function refresh() {
  refreshPending.value = true
  await execute('refresh_codex')
  refreshPending.value = false
}
const period = ref(24)
const availableCredits = computed(() => (props.state.quota.resetCredits?.credits ?? []).filter(credit => credit.status === 'available' && credit.resetType === 'codexRateLimits').sort((a, b) => (a.expiresAt ?? Infinity) - (b.expiresAt ?? Infinity)))
const nextExpiringCredit = computed(() => availableCredits.value.find(credit => credit.expiresAt !== null && credit.expiresAt > props.now))
function deadlineTone(deadline: number | null) {
  if (deadline === null) return undefined
  const remaining = deadline - props.now
  return remaining > 86400 ? 'normal' : remaining > 21600 ? 'warning' : remaining > 3600 ? 'urgent' : 'critical'
}
const tone = (used: number) => used >= 100 ? 'exhausted' : used >= 80 ? 'warning' : 'normal'
const chartNow = computed(() => Math.floor(props.now / 60) * 60)
const chartEnd = computed(() => Math.max(chartNow.value, props.state.quota.lastSuccess ?? 0))
const visiblePoints = (series: QuotaSeries) => series.points.filter(point => point.date >= chartNow.value - period.value * 3600 && point.date <= chartEnd.value)
const hovered = ref<Record<string, { date: number; used: number | null } | null>>({})
function inspectSample(series: QuotaSeries, hover: ChartTimeHover | null) {
  if (!hover) { hovered.value[series.window.id] = null; return }
  const date = hover.timestamp / 1000
  let closest: QuotaSeries['points'][number] | undefined
  for (const point of visiblePoints(series)) {
    if (!closest || Math.abs(point.date - date) < Math.abs(closest.date - date)) closest = point
  }
  // Match the native chart's 12-pixel hit area; a gap must not borrow a distant reading.
  const sample = closest && Math.abs(closest.date - date) * 1000 <= hover.tolerance ? closest : null
  hovered.value[series.window.id] = { date: sample?.date ?? date, used: sample?.usedPercent ?? null }
}
function trend(series: QuotaSeries): EChartsCoreOption {
  const points = visiblePoints(series)
  const segments = [...new Set(points.map(point => point.segment))]
  return {
    grid: { left: 42, right: 12, top: 14, bottom: 28 },
    tooltip: { trigger: 'axis', showContent: false, axisPointer: { type: 'line', snap: false } },
    xAxis: { type: 'time', min: (chartNow.value - period.value * 3600) * 1000, max: chartEnd.value * 1000, axisPointer: { triggerEmphasis: false }, axisTick: { show: false }, axisLine: { show: false }, axisLabel: { hideOverlap: true, showMinLabel: false, showMaxLabel: false, formatter: (value: number) => new Date(value).toLocaleString('zh-CN', period.value === 24 ? { hour: '2-digit', minute: '2-digit' } : { month: '2-digit', day: '2-digit' }) } },
    yAxis: { type: 'value', min: 0, max: 100, interval: 50, axisLabel: { formatter: '{value}%' }, splitLine: { lineStyle: { color: '#88888820' } } },
    series: segments.map(segment => ({ name: quotaLabel(series.window.durationMinutes, series.window.label), type: 'line', symbol: 'circle', symbolSize: 4, showSymbol: true, connectNulls: false, lineStyle: { width: 2, color: series.window.usedPercent >= 100 ? '#c33f53' : series.window.usedPercent >= 80 ? '#b87530' : '#647d93' }, itemStyle: { color: series.window.usedPercent >= 100 ? '#c33f53' : series.window.usedPercent >= 80 ? '#b87530' : '#647d93' }, data: points.filter(point => point.segment === segment).map(point => [point.date * 1000, point.usedPercent]) })),
  }
}
const quotaCharts = computed(() => Object.values(props.state.quota.history).map(series => ({ series, option: trend(series), latest: visiblePoints(series).at(-1) })))
</script>
<template>
  <div class="quota-page">
    <div v-if="!state.settings.monitoringEnabled" class="notice">Codex 监测已关闭，可在设置中开启。</div>
    <div v-if="state.quota.error" class="notice warning" role="status">{{ state.quota.error }}<span v-if="state.quota.lastSuccess"> 上次读数已过期。</span></div>
    <section class="surface quota-surface"><div class="section-heading"><h2>Codex</h2><div class="setting-actions"><span class="muted">剩余</span><Button variant="outline" size="sm" :disabled="!state.settings.monitoringEnabled || refreshing" @click="refresh"><RefreshCw :size="14" :class="{ spinning: refreshing }" />{{ refreshing ? '读取中…' : '刷新' }}</Button></div></div>
      <div v-if="!state.quota.windows.length" class="empty-state">{{ refreshing ? '正在读取 Codex 额度…' : state.settings.monitoringEnabled ? '尚无可用额度数据，请确认 Codex 已登录。' : '暂无额度数据' }}</div>
      <div v-for="window in state.quota.windows" :key="window.id" class="quota-window" :class="tone(window.usedPercent)">
        <div class="quota-label-row"><h3>{{ quotaLabel(window.durationMinutes, window.label) }}<small v-if="window.bucket !== 'codex'">{{ window.name }}</small></h3><strong>{{ Math.floor(100 - window.usedPercent) }}%</strong></div>
        <div class="quota-track" aria-hidden="true"><div :style="{ width: `${100 - window.usedPercent}%` }" /></div>
        <div class="quota-time-row"><span class="deadline-countdown" :data-tone="deadlineTone(window.resetsAt)">{{ countdown(window.resetsAt, now) }}</span><span v-if="window.resetsAt" class="muted">重置 · {{ dateText(window.resetsAt) }}</span></div>
      </div>
      <div v-if="state.quota.resetCredits" class="credits">
        <div class="section-heading"><h3>重置卡</h3><span>{{ state.quota.resetCredits.availableCount }} 张可用</span></div>
        <div v-for="credit in availableCredits" :key="credit.id" class="credit-row">
          <span>{{ credit.expiresAt != null && credit.expiresAt <= now ? '已到期' : '可用重置卡' }}</span>
          <span class="credit-expiry"><span v-if="credit.id === nextExpiringCredit?.id" class="deadline-countdown" :data-tone="deadlineTone(credit.expiresAt)">{{ countdown(credit.expiresAt, now) }}</span><span class="muted">{{ credit.expiresAt != null ? `到期 · ${dateText(credit.expiresAt)}` : '到期时间未知' }}</span></span>
        </div>
        <p v-if="availableCredits.length < state.quota.resetCredits.availableCount" class="muted">到期明细不完整</p>
      </div>
      <div v-if="state.quota.lastSuccess !== null" class="quota-updated muted">上次读取 · {{ dateText(state.quota.lastSuccess, true) }}</div>
    </section>
    <AntigravityPanel :state="state" :now="now" />
    <section class="surface"><div class="section-heading"><h2>Codex 额度消耗趋势</h2><SlidingSelection v-slot="{ highlight }" :selection="period" class="segmented equal-options" role="group" aria-label="额度趋势时间范围"><component :is="highlight ? 'span' : 'label'" class="segment-option" :data-selected="period === 24"><input v-if="!highlight" v-model="period" class="sr-only" type="radio" name="quota-period" :value="24" />24 小时</component><component :is="highlight ? 'span' : 'label'" class="segment-option" :data-selected="period === 168"><input v-if="!highlight" v-model="period" class="sr-only" type="radio" name="quota-period" :value="168" />7 天</component></SlidingSelection></div><div v-if="!Object.keys(state.quota.history).length" class="empty-state chart-empty">成功读取额度后开始积累趋势</div><div v-for="{ series, option, latest } in quotaCharts" :key="series.window.id" class="quota-chart"><div class="quota-chart-heading"><span>{{ quotaLabel(series.window.durationMinutes, series.window.label) }}</span><span v-if="hovered[series.window.id]">{{ dateText(hovered[series.window.id]!.date) }} · {{ hovered[series.window.id]!.used === null ? '无采样' : `已用 ${hovered[series.window.id]!.used!.toLocaleString('zh-CN', { maximumFractionDigits: 1 })}%` }}</span><span v-else>{{ latest ? `已用 ${latest.usedPercent.toLocaleString('zh-CN', { maximumFractionDigits: 1 })}%` : '无采样' }}</span></div><Chart :option="option" time-hover @time-hover="inspectSample(series, $event)" :label="`${quotaLabel(series.window.durationMinutes, series.window.label)}已用百分比趋势；中断时段不连接`" :height="120" :animations="state.settings.animations" /></div></section>
    <AnnouncementPanel :feed="state.announcements" service="Codex" :now="now" />
    <AnnouncementPanel v-if="state.settings.antigravityEnabled || state.antigravityAnnouncements.events.length" :feed="state.antigravityAnnouncements" service="Antigravity" :now="now" />
  </div>
</template>
