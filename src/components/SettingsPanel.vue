<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { useEventListener } from '@vueuse/core'
import { ArrowUpRight, ChevronDown } from '@lucide/vue'
import type { AppSnapshot, Settings } from '@/types'
import { actionError, cancelUpdate, changeSettings, checkForUpdates, execute, isPreview, notificationGuideOpen, notificationStatus, openExternal, readNotificationStatus, requestNotificationsIfNeeded, systemCommand } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Checkbox } from '@/components/ui/checkbox'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'
import PricingDialog from './PricingDialog.vue'
import DetailColumnsMenu from './DetailColumnsMenu.vue'
import ReleaseNotes from './ReleaseNotes.vue'
import ReminderSchedule from './ReminderSchedule.vue'

const props = defineProps<{ state: AppSnapshot }>()
const intervalOpen = ref(false)
const intervalDraft = ref(props.state.settings.refreshInterval)
const intervalSelection = ref<string | number>(props.state.settings.refreshInterval)
const pricingOpen = ref(false)
const clearOpen = ref(false)
const intervals = [{ value: 30, label: '30 秒' }, { value: 60, label: '1 分钟' }, { value: 120, label: '2 分钟' }, { value: 300, label: '5 分钟' }, { value: 600, label: '10 分钟' }, { value: 1800, label: '30 分钟' }]
const metrics = [{ value: 'tokens', label: 'Token' }, { value: 'cost', label: '估算费用' }, { value: 'records', label: '用量记录数' }, { value: 'hitRate', label: '缓存命中率' }]
const selectedMetrics = computed(() => metrics.filter(item => props.state.settings.todayMetrics.includes(item.value)).map(item => item.label).join('、') || '不显示')
const permissionText = computed(() => {
  const status = notificationStatus.value
  if (isPreview) return '离线预览'
  if (!status) return '无法确认通知权限'
  if (status.permission === 'system') return '由系统管理'
  if (status.permission === 'denied') return '通知未获允许，请在系统设置中开启'
  if (status.permission === 'prompt') return '尚未允许系统通知'
  return { persistent: '持久通知已开启，提醒保留到手动关闭', banner: '临时横幅，提醒会自动消失', disabled: '已允许通知，未开启桌面提醒', unknown: '已允许通知，无法确认提醒样式' }[status.alertStyle]
})
async function testNotification() {
  await requestNotificationsIfNeeded()
  if (actionError.value) return
  await systemCommand('test_notification')
  if (!actionError.value) await readNotificationStatus()
}
useEventListener(window, 'focus', readNotificationStatus)
onMounted(readNotificationStatus)
async function selectInterval(value: string) {
  intervalSelection.value = value
  if (value === 'custom') { intervalDraft.value = props.state.settings.refreshInterval; intervalOpen.value = true }
  else await changeSettings({ refreshInterval: Number(value) })
  // Let NativeSelect receive the action value before restoring the saved interval.
  await nextTick()
  intervalSelection.value = props.state.settings.refreshInterval
}
async function saveInterval() { if (Number.isInteger(intervalDraft.value) && intervalDraft.value >= 30) { await changeSettings({ refreshInterval: intervalDraft.value }); if (!actionError.value) intervalOpen.value = false } }
function selectMany(key: 'todayMetrics' | 'detailColumns', value: string, checked: boolean | 'indeterminate') {
  const selected = props.state.settings[key].filter(item => item !== value)
  if (checked === true) selected.push(value)
  void changeSettings({ [key]: selected })
}
async function notifications(key: keyof Settings, value: boolean) {
  await changeSettings({ [key]: value })
  if (value && !actionError.value) await requestNotificationsIfNeeded()
}
watch(() => props.state.settings.refreshInterval, value => { intervalSelection.value = value })
</script>
<template>
  <div class="settings-page">
    <section class="surface settings-section"><div class="section-heading"><h2 id="monitoring-label">Codex 额度监测</h2><Switch id="monitoring" aria-labelledby="monitoring-label" :model-value="state.settings.monitoringEnabled" @update:model-value="changeSettings({ monitoringEnabled: $event })" /></div><fieldset class="dependent-settings" :disabled="!state.settings.monitoringEnabled"><div class="setting-row"><span id="recovery-label">额度恢复时通知</span><Switch id="recovery" aria-labelledby="recovery-label" :model-value="state.settings.recoveryNotifications" :disabled="!state.settings.monitoringEnabled" @update:model-value="notifications('recoveryNotifications', $event)" /></div><div class="setting-row"><span id="credits-label">重置卡到期前提醒</span><Switch id="credits" aria-labelledby="credits-label" :model-value="state.settings.resetCreditReminders" :disabled="!state.settings.monitoringEnabled" @update:model-value="notifications('resetCreditReminders', $event)" /></div>
      <ReminderSchedule v-if="state.settings.resetCreditReminders" id="credits-reminder" labelledby="credits-label" :minutes="state.settings.resetCreditReminderMinutes" setting="resetCreditReminderMinutes" :disabled="!state.settings.monitoringEnabled" />
      <div class="setting-row"><span id="quota-reset-label">额度重置前提醒</span><Switch id="quota-reset" aria-labelledby="quota-reset-label" :model-value="state.settings.quotaResetReminders" :disabled="!state.settings.monitoringEnabled" @update:model-value="notifications('quotaResetReminders', $event)" /></div>
      <ReminderSchedule v-if="state.settings.quotaResetReminders" id="quota-reset-reminder" labelledby="quota-reset-label" :minutes="state.settings.quotaResetReminderMinutes" setting="quotaResetReminderMinutes" :disabled="!state.settings.monitoringEnabled" />
      <p v-if="state.settings.quotaResetReminders" class="muted reminder-note">仅提醒未用完的额度；提前时间须短于额度周期。</p>
      <div class="setting-row"><span id="announcement-notifications-label">Codex 重置动态通知</span><Switch id="announcement-notifications" aria-labelledby="announcement-notifications-label" :model-value="state.settings.announcementNotifications" :disabled="!state.settings.monitoringEnabled" @update:model-value="notifications('announcementNotifications', $event)" /></div></fieldset></section>
    <section class="surface settings-section">
      <div class="section-heading"><h2 id="antigravity-monitoring-label">Antigravity 额度监测</h2><Switch id="antigravity-monitoring" aria-labelledby="antigravity-monitoring-label" :model-value="state.settings.antigravityEnabled" @update:model-value="changeSettings({ antigravityEnabled: $event })" /></div>
      <div class="setting-row"><span id="antigravity-announcements-label">Antigravity 重置动态通知</span><Switch aria-labelledby="antigravity-announcements-label" :model-value="state.settings.antigravityAnnouncementNotifications" :disabled="!state.settings.antigravityEnabled" @update:model-value="notifications('antigravityAnnouncementNotifications', $event)" /></div>
      <p class="muted">需先安装官方 agy 并在终端登录。当前仅展示额度，不记录历史或提醒恢复。</p>
    </section>
    <section class="surface settings-section"><div class="section-heading"><h2>系统通知</h2><span>{{ permissionText }}</span></div><div class="setting-actions"><Button variant="outline" size="sm" :disabled="!(state.settings.monitoringEnabled && (state.settings.recoveryNotifications || state.settings.resetCreditReminders || state.settings.quotaResetReminders || state.settings.announcementNotifications) || state.settings.antigravityEnabled && state.settings.antigravityAnnouncementNotifications)" @click="testNotification">测试通知</Button><Button v-if="(isPreview || state.platform === 'macos') && notificationStatus?.alertStyle !== 'persistent'" variant="outline" size="sm" @click="notificationGuideOpen = true">持久通知…</Button><Button variant="outline" size="sm" @click="systemCommand('open_notification_settings')">系统设置…</Button></div></section>
    <section class="surface settings-section"><h2>通用</h2><div class="setting-row"><label for="refresh-interval">刷新间隔</label><Popover v-model:open="intervalOpen"><PopoverAnchor as-child><NativeSelect id="refresh-interval" :model-value="intervalSelection" @change="selectInterval(($event.target as HTMLSelectElement).value)"><NativeSelectOption v-for="item in intervals" :key="item.value" :value="item.value">{{ item.label }}</NativeSelectOption><NativeSelectOption v-if="!intervals.some(item => item.value === state.settings.refreshInterval)" :value="state.settings.refreshInterval">{{ state.settings.refreshInterval }} 秒</NativeSelectOption><NativeSelectOption value="custom">自定义…</NativeSelectOption></NativeSelect></PopoverAnchor><PopoverContent class="interval-popover" align="end"><form @submit.prevent="saveInterval"><label class="field" for="custom-interval">刷新间隔（秒）<input id="custom-interval" v-model.number="intervalDraft" type="number" min="30" step="1" required autofocus /></label><p class="muted">最低 30 秒</p><div class="dialog-actions"><Button size="sm" type="button" variant="outline" @click="intervalOpen = false">取消</Button><Button size="sm" type="submit">保存</Button></div></form></PopoverContent></Popover></div><div class="setting-row"><span id="show-tray-label">{{ state.platform === 'windows' ? '系统托盘显示 Codex' : '菜单栏显示 Codex' }}</span><Switch id="show-tray" aria-labelledby="show-tray-label" :model-value="state.settings.showTray" @update:model-value="changeSettings({ showTray: $event })" /></div><div class="setting-row"><span id="antigravity-tray-label">{{ state.platform === 'windows' ? '系统托盘显示 Antigravity' : '菜单栏显示 Antigravity' }}</span><Switch aria-labelledby="antigravity-tray-label" :model-value="state.settings.antigravityShowTray" @update:model-value="changeSettings({ antigravityShowTray: $event })" /></div><div class="setting-row"><span id="autostart-label">登录时启动</span><Switch id="autostart" aria-labelledby="autostart-label" :model-value="state.settings.launchAtLogin" @update:model-value="changeSettings({ launchAtLogin: $event })" /></div><div class="setting-row"><span id="animations-label" title="图表与界面过渡动画；遵循系统减少动态效果设置。">动画特性</span><Switch id="animations" aria-labelledby="animations-label" :model-value="state.settings.animations" @update:model-value="changeSettings({ animations: $event })" /></div></section>
    <section class="surface settings-section"><h2>用量显示</h2><div class="setting-row"><span>侧栏今日用量</span><Popover><PopoverTrigger as-child><Button variant="outline" size="sm" :aria-label="`侧栏今日用量：${selectedMetrics}`">{{ selectedMetrics }}<ChevronDown aria-hidden="true" /></Button></PopoverTrigger><PopoverContent class="choices-popover" align="end"><label v-for="item in metrics" :key="item.value" class="checkbox-row"><Checkbox :model-value="state.settings.todayMetrics.includes(item.value)" @update:model-value="selectMany('todayMetrics', item.value, $event)" />{{ item.label }}</label></PopoverContent></Popover></div><div class="setting-row"><span>明细可选列</span><DetailColumnsMenu :selected="state.settings.detailColumns" /></div></section>
    <section class="surface settings-section"><div class="setting-row"><h2>模型定价</h2><Button variant="outline" size="sm" @click="pricingOpen = true">管理定价…</Button></div></section>
    <section class="surface settings-section"><h2>用量历史</h2><div class="setting-actions"><Button variant="outline" size="sm" :disabled="state.usage.refreshing" @click="execute('scan_usage', { rescan: true })">重新扫描日志</Button><Button variant="outline" size="sm" @click="clearOpen = true">清除已保存历史…</Button></div></section>
    <section class="surface settings-section"><div class="section-heading"><h2>软件更新 <span class="version">{{ state.version }}</span></h2><div class="setting-actions"><Button v-if="state.update.status === 'checking'" variant="outline" size="sm" @click="cancelUpdate">取消检查</Button><Button v-else-if="state.update.status === 'downloading'" variant="outline" size="sm" @click="cancelUpdate">取消下载</Button><Button v-else variant="outline" size="sm" :disabled="state.update.status === 'installing'" @click="checkForUpdates">检查更新</Button><Button v-if="state.update.canInstall" size="sm" variant="outline" :disabled="['downloading', 'installing'].includes(state.update.status)" @click="execute('install_update')">下载并安装…</Button></div></div><div class="update-status"><button class="text-link" @click="openExternal('https://github.com/sunpm/codex-quota/releases')">发布页 <ArrowUpRight :size="13" /></button><span :title="state.update.error ?? ''">{{ state.update.error ?? ({ idle: '', checking: '正在检查…', available: `发现新版本 ${state.update.version}`, current: '已是最新版本', downloading: `正在下载${state.update.progress != null ? ` ${Math.round(state.update.progress)}%` : ''}`, installing: '正在安装…', error: '检查失败' }[state.update.status]) }}</span></div><div v-if="state.update.status === 'downloading'" class="download-track"><div :style="{ width: `${state.update.progress ?? 0}%` }" /></div><div v-if="state.update.version && state.update.notes" class="release-notes"><ReleaseNotes :notes="state.update.notes" /></div><div class="setting-row update-toggle"><span id="auto-update-label">自动检查更新</span><Switch id="auto-update" aria-labelledby="auto-update-label" :model-value="state.settings.automaticUpdates" @update:model-value="changeSettings({ automaticUpdates: $event })" /></div></section>
    <PricingDialog v-model:open="pricingOpen" :state="state" />
    <Dialog v-model:open="clearOpen"><DialogContent><DialogHeader><DialogTitle>清除已保存历史？</DialogTitle><DialogDescription>只清除本应用保存的 Codex 用量历史。源日志保持不变，下次扫描会重新采集仍在本机的记录。</DialogDescription></DialogHeader><div class="dialog-actions"><Button variant="outline" @click="clearOpen = false">取消</Button><Button variant="destructive" @click="execute('clear_history').then(() => { if (!actionError) clearOpen = false })">清除历史</Button></div></DialogContent></Dialog>

  </div>
</template>

<style scoped>
.release-notes { white-space: normal; }
.reminder-note { margin: -4px 0 12px; font-size: 12px; }
</style>
