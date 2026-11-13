import { computed, shallowRef } from 'vue'
import { invoke, isTauri } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import type { AppSnapshot, NotificationStatus, Settings } from '@/types'
import { emptySnapshot, previewSnapshot } from './preview'

export const isDesktop = isTauri()
export const isPreview = !isDesktop && new URLSearchParams(location.search).has('preview')
export const snapshot = shallowRef<AppSnapshot>(isPreview ? previewSnapshot() : emptySnapshot())
export const actionError = shallowRef<string | null>(null)
export const manualUpdateCheck = shallowRef(false)
export const connected = shallowRef(isPreview)
export const settings = computed(() => snapshot.value.settings)
export const notificationStatus = shallowRef<NotificationStatus | null>(null)
export const notificationGuideOpen = shallowRef(false)
export async function initialize() {
  if (!isDesktop) return
  const unlisten = await listen<AppSnapshot>('app-state', event => { snapshot.value = event.payload; connected.value = true })
  await execute('get_snapshot')
  const preferences = snapshot.value.settings
  if (preferences.monitoringEnabled && (preferences.recoveryNotifications || preferences.resetCreditReminders || preferences.quotaResetReminders || preferences.announcementNotifications) || preferences.antigravityEnabled && preferences.antigravityAnnouncementNotifications) {
    await requestNotificationsIfNeeded()
  }
  return unlisten
}
export async function execute(command: string, args?: Record<string, unknown>) {
  actionError.value = null
  if (isPreview) {
    if (command === 'save_settings') snapshot.value = { ...snapshot.value, settings: args?.settings as Settings }
    else if (command === 'save_prices') {
      const prices = args?.prices as AppSnapshot['prices']
      snapshot.value = { ...snapshot.value, prices: [...snapshot.value.prices.filter(price => !prices.some(updated => updated.model === price.model)), ...prices] }
    }
    else if (command === 'reset_price') { const original = previewSnapshot().prices.find(price => price.model === args?.model); snapshot.value = { ...snapshot.value, prices: [...snapshot.value.prices.filter(price => price.model !== args?.model), ...(original ? [original] : [])] } }
    else if (command === 'clear_history') snapshot.value = { ...snapshot.value, usage: { ...snapshot.value.usage, records: [] } }
    else if (command === 'scan_usage') snapshot.value = { ...snapshot.value, usage: previewSnapshot().usage }
    else if (command === 'refresh_codex') snapshot.value = { ...snapshot.value, quota: { ...snapshot.value.quota, lastSuccess: Date.now() / 1000, error: null } }
    else if (command === 'cancel_update') snapshot.value = { ...snapshot.value, update: { ...snapshot.value.update, status: 'idle' } }
    else if (command === 'check_update') snapshot.value = { ...snapshot.value, update: { ...snapshot.value.update, status: 'current' } }
    else if (command === 'mark_notification_guide_shown') snapshot.value = { ...snapshot.value, notificationGuideShown: true }
    return
  }
  if (!isDesktop) { actionError.value = '请在 Codex Quota 桌面应用中操作。'; return }
  await invoke<AppSnapshot>(command, args).then(value => {
    snapshot.value = value; connected.value = true
  }, error => { actionError.value = String(error) })
}
export async function systemCommand<T = void>(command: string, args?: Record<string, unknown>): Promise<T | undefined> {
  actionError.value = null
  if (isPreview) return undefined
  if (!isDesktop) { actionError.value = '请在 Codex Quota 桌面应用中操作。'; return undefined }
  return invoke<T>(command, args).catch(error => { actionError.value = String(error); return undefined })
}
export const changeSettings = (patch: Partial<Settings>) => execute('save_settings', { settings: { ...snapshot.value.settings, ...patch } })
export const openExternal = (url: string) => systemCommand('open_external', { url })

export async function readNotificationStatus() {
  if (!isDesktop) return
  const status = await systemCommand<NotificationStatus>('notification_permission')
  notificationStatus.value = status ?? null
  return status
}

// Startup, reminder switches and the test button share the same first-authorization flow.
export async function requestNotificationsIfNeeded() {
  const before = await readNotificationStatus()
  if (before?.permission !== 'prompt') return
  const status = await systemCommand<NotificationStatus>('request_notification_permission')
  if (!status) return
  notificationStatus.value = status
  if (status.permission === 'granted' && status.alertStyle !== 'persistent' && !snapshot.value.notificationGuideShown) {
    notificationGuideOpen.value = true
  }
}

export async function checkForUpdates() {
  manualUpdateCheck.value = true
  snapshot.value = { ...snapshot.value, update: { ...snapshot.value.update, status: 'checking' } }
  await execute('check_update')
  if (actionError.value) manualUpdateCheck.value = false
}
export async function cancelUpdate() {
  manualUpdateCheck.value = false
  await execute('cancel_update')
}
