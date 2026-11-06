<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { useEventListener } from '@vueuse/core'
import { ArrowUpRight } from '@lucide/vue'
import type { AppSnapshot, Settings } from '@/types'
import { actionError, cancelUpdate, changeSettings, checkForUpdates, execute, isPreview, openExternal, systemCommand } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { Checkbox } from '@/components/ui/checkbox'
import { Popover, PopoverAnchor, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'
import PricingDialog from './PricingDialog.vue'
import ReleaseNotes from './ReleaseNotes.vue'

const props = defineProps<{ state: AppSnapshot }>()
const notificationStatus = ref<{ permission: 'system' | 'granted' | 'denied' | 'prompt'; persistent: boolean } | null>(null)
const intervalOpen = ref(false)
const intervalDraft = ref(300)
const pricingOpen = ref(false)
const clearOpen = ref(false)
const guideOpen = ref(false)
const intervals = [{ value: 30, label: '30 秒' }, { value: 60, label: '1 分钟' }, { value: 120, label: '2 分钟' }, { value: 300, label: '5 分钟' }, { value: 600, label: '10 分钟' }, { value: 1800, label: '30 分钟' }]
const metrics = [{ value: 'tokens', label: 'Token' }, { value: 'cost', label: '估算费用' }, { value: 'records', label: '用量记录数' }, { value: 'hitRate', label: '缓存命中率' }]
const columns = [{ value: 'speed', label: '速度' }, { value: 'firstToken', label: '首字' }, { value: 'cacheWrite', label: '缓存写入' }, { value: 'billingTier', label: '计费档位' }]
const permissionText: Record<string, string> = { system: '由系统管理', granted: '已允许系统通知', denied: '通知未获允许', prompt: '尚未允许系统通知', default: '尚未允许系统通知' }
async function readPermission() {
  if (!isPreview) notificationStatus.value = await systemCommand<NonNullable<typeof notificationStatus.value>>('notification_permission') ?? null
}
async function testNotification() {
  await systemCommand('test_notification')
  if (!actionError.value) await readPermission()
}
useEventListener(window, 'focus', readPermission)
onMounted(readPermission)
function selectInterval(event: Event) {
  const value = (event.target as HTMLSelectElement).value
  if (value === 'saved-custom') return
  if (value === 'custom') { (event.target as HTMLSelectElement).value = intervals.some(item => item.value === props.state.settings.refreshInterval) ? String(props.state.settings.refreshInterval) : 'saved-custom'; intervalDraft.value = props.state.settings.refreshInterval; intervalOpen.value = true }
  else void changeSettings({ refreshInterval: Number(value) })
}
async function saveInterval() { if (Number.isInteger(intervalDraft.value) && intervalDraft.value >= 30) { await changeSettings({ refreshInterval: intervalDraft.value }); if (!actionError.value) intervalOpen.value = false } }
function selectMany(key: 'todayMetrics' | 'detailColumns', value: string, checked: boolean | 'indeterminate') {
  const selected = props.state.settings[key].filter(item => item !== value)
  if (checked === true) selected.push(value)
  void changeSettings({ [key]: selected })
}
async function notifications(key: keyof Settings, value: boolean) {
  await changeSettings({ [key]: value })
  if (value) { await systemCommand('request_notification_permission'); await readPermission() }
}
watch(() => props.state.settings.monitoringEnabled, enabled => { if (!enabled) intervalOpen.value = false })
</script>
<template>
  <div class="settings-page">
    <section class="surface settings-section"><div class="section-heading"><h2><label for="monitoring">额度监测</label></h2><Switch id="monitoring" :model-value="state.settings.monitoringEnabled" @update:model-value="changeSettings({ monitoringEnabled: $event })" /></div><fieldset class="dependent-settings" :disabled="!state.settings.monitoringEnabled"><div class="setting-row"><label for="refresh-interval">刷新间隔</label><Popover v-model:open="intervalOpen"><PopoverAnchor as-child><span class="interval-control"><select id="refresh-interval" class="native-select" :value="intervals.some(item => item.value === state.settings.refreshInterval) ? state.settings.refreshInterval : 'saved-custom'" @change="selectInterval"><option v-for="item in intervals" :key="item.value" :value="item.value">{{ item.label }}</option><option v-if="!intervals.some(item => item.value === state.settings.refreshInterval)" value="saved-custom">{{ state.settings.refreshInterval }} 秒</option><option value="custom">自定义…</option></select></span></PopoverAnchor><PopoverContent class="interval-popover" align="end"><form @submit.prevent="saveInterval"><label class="field" for="custom-interval">刷新间隔（秒）<input id="custom-interval" v-model.number="intervalDraft" type="number" min="30" step="1" required autofocus /></label><p class="muted">最低 30 秒</p><div class="dialog-actions"><Button size="sm" type="button" variant="outline" @click="intervalOpen = false">取消</Button><Button size="sm" type="submit">保存</Button></div></form></PopoverContent></Popover></div><div class="setting-row"><label for="recovery">额度恢复时通知</label><Switch id="recovery" :model-value="state.settings.recoveryNotifications" :disabled="!state.settings.monitoringEnabled" @update:model-value="notifications('recoveryNotifications', $event)" /></div><div class="setting-row"><label for="credits">重置卡到期前 24 小时提醒</label><Switch id="credits" :model-value="state.settings.resetCreditReminders" :disabled="!state.settings.monitoringEnabled" @update:model-value="notifications('resetCreditReminders', $event)" /></div><div class="setting-row"><label for="announcement-notifications">Codex 重置动态通知</label><Switch id="announcement-notifications" :model-value="state.settings.announcementNotifications" :disabled="!state.settings.monitoringEnabled" @update:model-value="notifications('announcementNotifications', $event)" /></div></fieldset></section>
    <section class="surface settings-section"><div class="section-heading"><h2>系统通知</h2><span>{{ isPreview ? '离线预览' : notificationStatus?.persistent ? '已开启持续通知' : permissionText[notificationStatus?.permission ?? ''] ?? '无法确认通知权限' }}</span></div><div class="setting-actions"><Button variant="outline" size="sm" :disabled="!state.settings.monitoringEnabled || !(state.settings.recoveryNotifications || state.settings.resetCreditReminders || state.settings.announcementNotifications)" @click="testNotification">测试通知</Button><Button v-if="!isPreview && state.platform === 'macos' && notificationStatus && !notificationStatus.persistent" variant="outline" size="sm" @click="guideOpen = true">持久通知…</Button><Button variant="outline" size="sm" @click="systemCommand('open_notification_settings')">系统设置…</Button></div></section>
    <section class="surface settings-section"><h2>通用</h2><div class="setting-row"><label for="show-tray">{{ state.platform === 'windows' ? '系统托盘显示额度' : '菜单栏显示额度' }}</label><Switch id="show-tray" :model-value="state.settings.showTray" @update:model-value="changeSettings({ showTray: $event })" /></div><div class="setting-row"><label for="autostart">登录时启动</label><Switch id="autostart" :model-value="state.settings.launchAtLogin" @update:model-value="changeSettings({ launchAtLogin: $event })" /></div><div class="setting-row"><label for="animations" title="图表与界面过渡动画；遵循系统减少动态效果设置。">动画特性</label><Switch id="animations" :model-value="state.settings.animations" @update:model-value="changeSettings({ animations: $event })" /></div></section>
    <section class="surface settings-section"><h2>用量显示</h2><div class="setting-row"><span>侧栏今日用量</span><Popover><PopoverTrigger as-child><Button variant="outline" size="sm">{{ state.settings.todayMetrics.length ? `已选 ${state.settings.todayMetrics.length} 项` : '不显示' }}</Button></PopoverTrigger><PopoverContent class="choices-popover" align="end"><label v-for="item in metrics" :key="item.value" class="checkbox-row"><Checkbox :model-value="state.settings.todayMetrics.includes(item.value)" @update:model-value="selectMany('todayMetrics', item.value, $event)" />{{ item.label }}</label></PopoverContent></Popover></div><div class="setting-row"><span>明细可选列</span><Popover><PopoverTrigger as-child><Button variant="outline" size="sm">已选 {{ state.settings.detailColumns.length }} 项</Button></PopoverTrigger><PopoverContent class="choices-popover" align="end"><label v-for="item in columns" :key="item.value" class="checkbox-row"><Checkbox :model-value="state.settings.detailColumns.includes(item.value)" @update:model-value="selectMany('detailColumns', item.value, $event)" />{{ item.label }}</label></PopoverContent></Popover></div></section>
    <section class="surface settings-section"><div class="setting-row"><h2>模型定价</h2><Button variant="outline" size="sm" @click="pricingOpen = true">管理定价…</Button></div></section>
    <section class="surface settings-section"><h2>用量历史</h2><div class="setting-actions"><Button variant="outline" size="sm" :disabled="state.usage.refreshing" @click="execute('scan_usage', { rescan: true })">重新扫描日志</Button><Button variant="outline" size="sm" @click="clearOpen = true">清除已保存历史…</Button></div></section>
    <section class="surface settings-section"><div class="section-heading"><h2>软件更新 <span class="version">{{ state.version }}</span></h2><div class="setting-actions"><Button v-if="state.update.status === 'checking'" variant="outline" size="sm" @click="cancelUpdate">取消检查</Button><Button v-else-if="state.update.status === 'downloading'" variant="outline" size="sm" @click="cancelUpdate">取消下载</Button><Button v-else variant="outline" size="sm" :disabled="state.update.status === 'installing'" @click="checkForUpdates">检查更新</Button><Button v-if="state.update.canInstall" size="sm" variant="outline" :disabled="['downloading', 'installing'].includes(state.update.status)" @click="execute('install_update')">下载并安装…</Button></div></div><div class="update-status"><button class="text-link" @click="openExternal('https://github.com/sunpm/codex-quota/releases')">发布页 <ArrowUpRight :size="13" /></button><span :title="state.update.error ?? ''">{{ state.update.error ?? ({ idle: '', checking: '正在检查…', available: `发现新版本 ${state.update.version}`, current: '已是最新版本', downloading: `正在下载${state.update.progress != null ? ` ${Math.round(state.update.progress)}%` : ''}`, installing: '正在安装…', error: '检查失败' }[state.update.status]) }}</span></div><div v-if="state.update.status === 'downloading'" class="download-track"><div :style="{ width: `${state.update.progress ?? 0}%` }" /></div><div v-if="state.update.version && state.update.notes" class="release-notes"><ReleaseNotes :notes="state.update.notes" /></div><div class="setting-row update-toggle"><label for="auto-update">自动检查更新</label><Switch id="auto-update" :model-value="state.settings.automaticUpdates" @update:model-value="changeSettings({ automaticUpdates: $event })" /></div></section>
    <PricingDialog v-model:open="pricingOpen" :state="state" />
    <Dialog v-model:open="clearOpen"><DialogContent><DialogHeader><DialogTitle>清除已保存历史？</DialogTitle><DialogDescription>只清除本应用保存的 Codex 用量历史。源日志保持不变，下次扫描会重新采集仍在本机的记录。</DialogDescription></DialogHeader><div class="dialog-actions"><Button variant="outline" @click="clearOpen = false">取消</Button><Button variant="destructive" @click="execute('clear_history').then(() => { if (!actionError) clearOpen = false })">清除历史</Button></div></DialogContent></Dialog>
    <Dialog v-model:open="guideOpen"><DialogContent><DialogHeader><DialogTitle>持久通知</DialogTitle><DialogDescription>{{ state.platform === 'windows' ? '在 Windows 设置 → 系统 → 通知中允许 Codex Quota 显示通知横幅和通知中心提醒。' : '在系统设置 → 通知中选择 Codex Quota，开启允许通知，并将桌面提醒样式设为持续或提醒。' }}</DialogDescription></DialogHeader><div class="dialog-actions"><Button variant="outline" @click="guideOpen = false">取消</Button><Button @click="systemCommand('open_notification_settings'); guideOpen = false">前往设置…</Button></div></DialogContent></Dialog>

  </div>
</template>

<style scoped>
.release-notes { white-space: normal; }
</style>
