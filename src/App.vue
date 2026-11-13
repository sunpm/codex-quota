<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { ChartNoAxesCombined, List, ChartPie, Settings as SettingsIcon, RefreshCw, Download, X } from '@lucide/vue'
import { listen } from '@tauri-apps/api/event'
import type { Page } from './types'
import { actionError, connected, execute, initialize, isDesktop, isPreview, snapshot } from './lib/app'
import { countdownTickMs, dateText, percent, serviceName, shortTokens, shiftDay, startOfDay, summarize, summaryMoney } from './lib/usage'
import { restoreChartOverview, usageService, useUsageFilters } from './lib/usage-filters'
import { Button } from './components/ui/button'
import UsagePanel from './components/UsagePanel.vue'
import QuotaPanel from './components/QuotaPanel.vue'
import SettingsPanel from './components/SettingsPanel.vue'
import UpdateResultDialog from './components/UpdateResultDialog.vue'
import InstalledReleaseNotesDialog from './components/InstalledReleaseNotesDialog.vue'
import NotificationGuide from './components/NotificationGuide.vue'
import SlidingSelection from './components/SlidingSelection.vue'

const page = ref<Page>('overview')
const pageContent = ref<HTMLElement | null>(null)
const now = ref(Date.now() / 1000)
const startedAt = now.value
const navigation = [{ id: 'overview', label: '用量', icon: ChartNoAxesCombined }, { id: 'details', label: '明细', icon: List }, { id: 'quota', label: '额度', icon: ChartPie }, { id: 'settings', label: '设置', icon: SettingsIcon }] as const
const isUsage = computed(() => ['overview', 'details'].includes(page.value))
const { period: usagePeriod } = useUsageFilters(() => page.value)
const usageRefreshLabel = computed(() => {
  if (snapshot.value.usage.refreshing) return '刷新中…'
  if (snapshot.value.usage.scannedAt === null) return '刷新'
  const minutes = Math.max(0, Math.floor((now.value - snapshot.value.usage.scannedAt) / 60))
  if (minutes < 1) return '刚刚刷新'
  if (minutes < 60) return `${minutes} 分钟前刷新`
  if (minutes < 1440) return `${Math.floor(minutes / 60)} 小时前刷新`
  return `${Math.floor(minutes / 1440)} 天前刷新`
})
const title = computed(() => navigation.find(item => item.id === page.value)!.label)
// Calendar ranges stay stable between scans; rolling ranges follow the local clock.
const calendarKey = computed(() => {
  const date = new Date(now.value * 1000)
  return `${startOfDay(date).getTime() / 1000}|${date.getTimezoneOffset()}|${Intl.DateTimeFormat().resolvedOptions().timeZone}`
})
const usageClock = computed(() => ({
  now: isUsage.value && usagePeriod.value === '24h' ? now.value : Math.max(snapshot.value.usage.scannedAt ?? startedAt, Number(calendarKey.value.split('|')[0])),
  calendar: calendarKey.value,
}))
const serviceRecords = computed(() => snapshot.value.usage.records.filter(record => usageService.value === 'all' || record.service === usageService.value))
const todayAvailable = computed(() => snapshot.value.usage.scannedAt !== null)
const today = computed(() => {
  const from = startOfDay(new Date(usageClock.value.now * 1000)).getTime() / 1000
  return summarize(serviceRecords.value.filter(record => record.date >= from && record.date <= usageClock.value.now))
})
const todayItems = computed(() => [
  { key: 'tokens', label: 'Token', value: shortTokens(today.value.tokens), title: today.value.tokens.toLocaleString('zh-CN') },
  { key: 'cost', label: '估算费用', value: summaryMoney(today.value), title: 'API 等价估算，非订阅账单' },
  { key: 'records', label: '用量记录数', value: `${shortTokens(today.value.count)} 条`, title: '已解析的用量事件数，不代表全部网络请求数' },
  { key: 'hitRate', label: '缓存命中率', value: percent(today.value.hitRate), title: '缓存命中 ÷ 全部输入' },
].filter(item => snapshot.value.settings.todayMetrics.includes(item.key)))
const sidebarWidth = ref(168)
const darkQuery = matchMedia('(prefers-color-scheme: dark)')
let unlisten: (() => void) | undefined
const menuListeners: (() => void)[] = []
let clock: ReturnType<typeof setTimeout> | undefined
function nextTickDelay(current: number) {
  const tomorrow = shiftDay(startOfDay(new Date(current * 1000)), 1).getTime() - current * 1000
  let delay = Math.max(1000, tomorrow)
  if (isUsage.value && usagePeriod.value === '24h') delay = Math.min(delay, 60_000)
  if (page.value === 'quota') {
    const deadlines = [
      ...snapshot.value.quota.windows.map(window => window.resetsAt),
      ...(snapshot.value.quota.resetCredits?.credits ?? []).filter(credit => credit.status === 'available' && credit.resetType === 'codexRateLimits').map(credit => credit.expiresAt),
      ...snapshot.value.antigravity.groups.flatMap(group => group.buckets.map(bucket => bucket.resetsAt)),
    ]
    const tick = countdownTickMs(deadlines, current)
    if (tick !== null) delay = Math.min(delay, tick)
    if (Object.keys(snapshot.value.quota.history).length) delay = Math.min(delay, 60_000)
  } else if (isUsage.value && snapshot.value.usage.scannedAt !== null) {
    const elapsed = Math.max(0, current - snapshot.value.usage.scannedAt)
    if (elapsed < 3600) delay = Math.min(delay, 60_000)
    else if (elapsed < 86400) delay = Math.min(delay, 3_600_000)
  }
  return delay
}
function scheduleClock() {
  clearTimeout(clock)
  const current = Date.now() / 1000
  now.value = current
  clock = setTimeout(scheduleClock, nextTickDelay(current))
}
watch(() => snapshot.value.settings.animations, enabled => document.documentElement.classList.toggle('no-animation', !enabled), { immediate: true })
watch(page, () => { pageContent.value?.scrollTo(0, 0); scheduleClock() }, { flush: 'post' })
watch(snapshot, scheduleClock)
watch(usagePeriod, scheduleClock)
function updateTheme() { document.documentElement.classList.toggle('dark', darkQuery.matches) }
function navigate(value: Page) { if (page.value === value) return; if (value === 'overview') restoreChartOverview(); page.value = value; if (value === 'quota') void execute('refresh_quota') }
function keydown(event: KeyboardEvent) {
  if (!(event.metaKey || event.ctrlKey)) return
  if (event.key === ',') { event.preventDefault(); navigate('settings') }
  else if (event.key.toLowerCase() === 'r') { event.preventDefault(); if (isUsage.value) void execute('scan_usage', { rescan: false }) }
}
function resizeSidebar(event: PointerEvent) {
  const handle = event.currentTarget as HTMLElement
  handle.setPointerCapture(event.pointerId)
  const move = (moveEvent: PointerEvent) => { sidebarWidth.value = Math.min(300, Math.max(168, moveEvent.clientX)) }
  const stop = () => { handle.removeEventListener('pointermove', move); handle.removeEventListener('pointerup', stop); handle.removeEventListener('pointercancel', stop) }
  handle.addEventListener('pointermove', move); handle.addEventListener('pointerup', stop); handle.addEventListener('pointercancel', stop)
}
onMounted(async () => {
  updateTheme(); darkQuery.addEventListener('change', updateTheme); window.addEventListener('keydown', keydown)
  scheduleClock()
  unlisten = await initialize().catch(error => { actionError.value = String(error); return undefined })
  if (isDesktop) {
    menuListeners.push(await listen<Page>('navigate', event => navigate(event.payload)))
    menuListeners.push(await listen('refresh-usage', () => { if (isUsage.value) void execute('scan_usage', { rescan: false }) }))
  }
})
onBeforeUnmount(() => { clearTimeout(clock); unlisten?.(); menuListeners.forEach(unsubscribe => unsubscribe()); darkQuery.removeEventListener('change', updateTheme); window.removeEventListener('keydown', keydown) })
</script>
<template>
  <div class="app-shell" :class="{ 'no-animation': !snapshot.settings.animations }" :style="{ '--sidebar-width': `${sidebarWidth}px` }">
    <aside class="sidebar"><SlidingSelection v-slot="{ highlight }" as="nav" :selection="page" aria-label="主导航"><component :is="highlight ? 'span' : 'button'" v-for="item in navigation" :key="item.id" class="nav-item" :class="{ selected: page === item.id, 'settings-nav': item.id === 'settings' }" :data-selected="page === item.id" :aria-current="!highlight && page === item.id ? 'page' : undefined" @click="navigate(item.id)"><component :is="item.icon" :size="17" :stroke-width="1.6" /><span>{{ item.label }}</span><Download v-if="item.id === 'settings' && snapshot.update.version" :size="13" class="update-dot" aria-label="有新版本" /></component></SlidingSelection><div class="sidebar-bottom"><div v-if="todayItems.length" class="today-summary"><h2 :title="serviceName(usageService)">今日 · {{ usageService === 'all' ? '全部' : serviceName(usageService) }}</h2><div v-for="item in todayItems" :key="item.key" :title="snapshot.usage.scannedAt === null ? '尚未读取本机日志' : item.title"><span>{{ item.label }}</span><strong>{{ todayAvailable ? item.value : '—' }}</strong></div></div><span v-if="isPreview" class="preview-label">离线预览 · 示例数据</span></div><div class="sidebar-resize" role="separator" aria-label="调整侧栏宽度" aria-orientation="vertical" tabindex="0" :aria-valuenow="sidebarWidth" :aria-valuemin="168" :aria-valuemax="300" @pointerdown="resizeSidebar" @keydown.left.prevent="sidebarWidth = Math.max(168, sidebarWidth - 8)" @keydown.right.prevent="sidebarWidth = Math.min(300, sidebarWidth + 8)" /></aside>
    <main class="main-panel"><header class="page-header"><h1>{{ title }}</h1><Button v-if="isUsage" variant="outline" size="sm" aria-label="刷新本机用量" :title="snapshot.usage.scannedAt === null ? undefined : `上次扫描：${dateText(snapshot.usage.scannedAt, true)}`" :disabled="snapshot.usage.refreshing || !isDesktop && !isPreview" @click="execute('scan_usage', { rescan: false })"><RefreshCw :size="14" :class="{ spinning: snapshot.usage.refreshing }" />{{ usageRefreshLabel }}</Button></header><div v-if="!isDesktop && !isPreview" class="notice browser-notice">浏览器无法访问本机用量。请启动桌面应用，或使用 <a href="?preview">离线预览</a> 查看示例界面。</div><div v-if="snapshot.error" class="notice warning app-notice" role="alert">{{ snapshot.error }}</div><div v-if="actionError" class="notice warning app-notice" role="alert"><span>{{ actionError }}</span><button aria-label="关闭提示" @click="actionError = null"><X :size="14" /></button></div><div ref="pageContent" class="page-content" :class="{ 'table-content': page === 'details' }" :aria-busy="isDesktop && !connected"><UsagePanel v-if="isUsage" :state="snapshot" :page="page" :clock="usageClock" @navigate="navigate" /><QuotaPanel v-else-if="page === 'quota'" :state="snapshot" :now="now" /><SettingsPanel v-else :state="snapshot" /></div></main>
    <UpdateResultDialog />
    <InstalledReleaseNotesDialog />
    <NotificationGuide />
  </div>
</template>
