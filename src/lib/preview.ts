import type { AppSnapshot, UsageRecord } from '@/types'
export function emptySnapshot(): AppSnapshot {
  return {
    settings: { monitoringEnabled: true, recoveryNotifications: true, resetCreditReminders: false, resetCreditReminderMinutes: [1440], quotaResetReminders: false, quotaResetReminderMinutes: [120], announcementNotifications: false, showTray: true, launchAtLogin: false, animations: true, refreshInterval: 60, automaticUpdates: true, todayMetrics: ['tokens'], detailColumns: ['speed', 'firstToken'] },
    quota: { windows: [], resetCredits: null, history: {}, error: null, lastSuccess: null, refreshing: false },
    announcements: { events: [], error: null, sourceStatus: null },
    usage: { records: [], projectRoots: {}, warnings: [], scannedAt: null, fileCount: 0, refreshing: false, source: '' },
    prices: [], priceDate: '', version: '0.23.0', platform: 'preview', update: { status: 'idle', version: null, notes: null, error: null, progress: null, canInstall: false }, installedReleaseNotes: null, notificationGuideShown: false,
  }
}
export function previewSnapshot(): AppSnapshot {
  const state = emptySnapshot()
  const now = Date.now() / 1000
  const models = ['gpt-6.1-sol', 'gpt-6.1-terra', 'gpt-6-luna']
  const records: UsageRecord[] = []
  for (let day = 0; day < 371; day++) {
    if (day % 7 === 6 || day % 11 === 0 && day > 0) continue
    for (let event = 0; event < (day < 7 ? 9 : 2); event++) {
      const date = new Date(); date.setDate(date.getDate() - day); date.setHours(day === 0 ? Math.max(0, date.getHours() - event) : 9 + event, 12, 0, 0)
      const input = 2100 + (day * 187 + event * 963) % 19000
      records.push({ id: `preview-${day}-${event}`, service: 'codex', session: `sample-${day}-${Math.floor(event / 3)}`, project: `/Projects/${['workspace', 'design-system', 'notes'][event % 3]}`, model: models[event % 3]!, date: Math.min(now, date.getTime() / 1000), tokens: { input, output: 1200 + event * 157, cached: input * 4, cacheWrite: 0, cacheWriteLong: 0, cacheWriteReported: false }, serviceTier: 'standard', isUSOnly: false, serviceTierReported: true, estimatedDuration: 16 + event, estimatedFirstToken: 1.2, cost: (input * 0.000004).toFixed(6) })
    }
  }
  state.usage = { records, projectRoots: {}, warnings: [], scannedAt: now, fileCount: 312, refreshing: false, source: '离线示例日志' }
  state.quota.windows = [{ id: 'codex:primary:300', bucket: 'codex', name: 'Codex', usedPercent: 28, durationMinutes: 300, resetsAt: now + 12700, label: null }, { id: 'codex:secondary:10080', bucket: 'codex', name: 'Codex', usedPercent: 63, durationMinutes: 10080, resetsAt: now + 276000, label: null }]
  for (const window of state.quota.windows) state.quota.history[window.id] = { window, points: Array.from({ length: 32 }, (_, index) => ({ date: now - (31 - index) * 900, usedPercent: Math.max(0, window.usedPercent - (31 - index) * .7), segment: index === 0 ? 1 : 2 })).filter((_, index) => index === 0 || index >= 8) }
  state.quota.lastSuccess = now
  state.quota.resetCredits = { availableCount: 1, credits: [{ id: 'sample-credit', resetType: 'codexRateLimits', status: 'available', expiresAt: now + 360000 }] }
  state.prices = models.map(model => ({ model, service: 'codex', rates: { input: '2.5', output: '15', cached: '0.25', cacheWrite: null, cacheWriteLong: null }, contextThreshold: null, longContextRates: null, fastMultiplier: '2', ultrafastMultiplier: null }))
  state.priceDate = '离线示例'
  return state
}
