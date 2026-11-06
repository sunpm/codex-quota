import { computed, shallowRef } from 'vue'
import { invoke, isTauri } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import type { AppSnapshot, Settings } from '@/types'
import { emptySnapshot, previewSnapshot } from './preview'

export const isDesktop = isTauri()
export const isPreview = !isDesktop && new URLSearchParams(location.search).has('preview')
export const snapshot = shallowRef<AppSnapshot>(isPreview ? previewSnapshot() : emptySnapshot())
export const actionError = shallowRef<string | null>(null)
export const manualUpdateCheck = shallowRef(false)
export const connected = shallowRef(isPreview)
export const settings = computed(() => snapshot.value.settings)
export async function initialize() {
  if (!isDesktop) return
  const unlisten = await listen<AppSnapshot>('app-state', event => { snapshot.value = event.payload; connected.value = true })
  await execute('get_snapshot')
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
    else if (command === 'cancel_update') snapshot.value = { ...snapshot.value, update: { ...snapshot.value.update, status: 'idle' } }
    else if (command === 'check_update') snapshot.value = { ...snapshot.value, update: { ...snapshot.value.update, status: 'current' } }
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
