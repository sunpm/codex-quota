import type { AppSnapshot, CostBreakdown, UsageRecord, UsageTokens } from '@/types'
import officialPrices from '../../crates/quota-core/src/official-pricing.json'
import { version } from '../../package.json'
const usageExamples: { model: string; tokens: UsageTokens; tier: string; detail: CostBreakdown }[] = [
  {
    model: 'gpt-6.1-sol', tier: 'standard',
    tokens: { input: 2100, output: 1200, cached: 8400, cacheWrite: 0, cacheWriteLong: 0, cacheWriteReported: false },
    detail: { pricingModel: 'gpt-6.1-sol', longContext: false, contextThreshold: null, multiplier: '1', total: '0.02535', components: [
      { kind: 'input', tokens: 2100, rate: '2.5', amount: '0.00525' },
      { kind: 'output', tokens: 1200, rate: '15', amount: '0.018' },
      { kind: 'cached', tokens: 8400, rate: '0.25', amount: '0.0021' },
      { kind: 'cacheWrite', tokens: 0, rate: null, amount: '0' },
      { kind: 'cacheWriteLong', tokens: 0, rate: null, amount: '0' },
    ] },
  },
  {
    model: 'gpt-6.1-terra', tier: 'fast',
    tokens: { input: 200000, output: 1200, cached: 10000, cacheWrite: 0, cacheWriteLong: 0, cacheWriteReported: false },
    detail: { pricingModel: 'gpt-6.1-terra', longContext: true, contextThreshold: 200000, multiplier: '2', total: '2.082', components: [
      { kind: 'input', tokens: 200000, rate: '5', amount: '2' },
      { kind: 'output', tokens: 1200, rate: '30', amount: '0.072' },
      { kind: 'cached', tokens: 10000, rate: '0.5', amount: '0.01' },
      { kind: 'cacheWrite', tokens: 0, rate: null, amount: '0' },
      { kind: 'cacheWriteLong', tokens: 0, rate: null, amount: '0' },
    ] },
  },
  {
    model: 'gpt-6-luna', tier: 'standard',
    tokens: { input: 2100, output: 1200, cached: 8400, cacheWrite: 0, cacheWriteLong: 0, cacheWriteReported: false },
    detail: { pricingModel: 'gpt-6-luna', longContext: false, contextThreshold: null, multiplier: '1', total: null, components: [
      { kind: 'input', tokens: 2100, rate: '2.5', amount: '0.00525' },
      { kind: 'output', tokens: 1200, rate: null, amount: null },
      { kind: 'cached', tokens: 8400, rate: '0.25', amount: '0.0021' },
      { kind: 'cacheWrite', tokens: 0, rate: null, amount: '0' },
      { kind: 'cacheWriteLong', tokens: 0, rate: null, amount: '0' },
    ] },
  },
]
export function previewCostBreakdown(record: UsageRecord): CostBreakdown {
  if (record.service === 'codex') return usageExamples.find(example => example.model === record.model)!.detail
  const unknown = record.model === 'unknown'
  return { pricingModel: unknown ? null : record.model, longContext: false, contextThreshold: null, multiplier: '1', total: record.cost, components: [
    { kind: 'input', tokens: 2100, rate: unknown ? null : '0.75', amount: unknown ? null : '0.001575' },
    { kind: 'output', tokens: record.tokens.output, rate: unknown ? null : '3.75', amount: unknown || record.tokens.outputReported === false ? null : '0.0045' },
    { kind: 'cached', tokens: 8400, rate: unknown ? null : '0.075', amount: unknown ? null : '0.00063' },
    { kind: 'cacheWrite', tokens: 0, rate: null, amount: '0' },
    { kind: 'cacheWriteLong', tokens: 0, rate: null, amount: '0' },
  ] }
}
export function emptySnapshot(): AppSnapshot {
  return {
    settings: { monitoringEnabled: true, antigravityEnabled: false, antigravityAnnouncementNotifications: false, antigravityShowTray: true, recoveryNotifications: true, lowQuotaNotifications: false, lowQuotaThreshold: 20, resetCreditReminders: false, resetCreditReminderMinutes: [1440], quotaResetReminders: false, quotaResetReminderMinutes: [120], announcementNotifications: false, showTray: true, launchAtLogin: false, animations: true, refreshInterval: 60, automaticUpdates: true, todayMetrics: ['tokens'], detailColumns: ['speed', 'firstToken'] },
    quota: { windows: [], resetCredits: null, history: {}, error: null, lastSuccess: null, refreshing: false },
    announcements: { events: [], error: null, sourceStatus: null, refreshing: false, lastSuccess: null },
    antigravity: { groups: [], error: null, lastSuccess: null, refreshing: false, requiresAction: false },
    antigravityAnnouncements: { events: [], error: null, sourceStatus: null, refreshing: false, lastSuccess: null },
    usage: { records: [], projectRoots: {}, sessionTitles: {}, warnings: [], scannedAt: null, fileCount: 0, refreshing: false, source: '' },
    prices: [], priceDate: '', version, platform: 'preview', update: { status: 'idle', version: null, notes: null, error: null, progress: null, canInstall: false }, installedReleaseNotes: null, notificationGuideShown: false,
  }
}
export function previewSnapshot(): AppSnapshot {
  const state = emptySnapshot()
  const now = Date.now() / 1000
  const sessionTitles: Record<string, string> = {}
  const records: UsageRecord[] = []
  for (let day = 0; day < 371; day++) {
    if (day % 7 === 6 || day % 11 === 0 && day > 0) continue
    for (let event = 0; event < (day < 7 ? 9 : 2); event++) {
      const date = new Date(); date.setDate(date.getDate() - day); date.setHours(day === 0 ? Math.max(0, date.getHours() - event) : 9 + event, 12, 0, 0)
      const example = usageExamples[(day + event) % usageExamples.length]!
      const session = `sample-${day}-${Math.floor(event / 3)}`
      if (day % 4 !== 3) sessionTitles[session] = ['优化额度卡片', '整理缓存统计', '修复分页交互'][Math.floor(event / 3)]!
      records.push({ id: `preview-${day}-${event}`, service: 'codex', session, project: `/Projects/${['workspace', 'design-system', 'notes'][event % 3]}`, model: example.model, date: Math.min(now, date.getTime() / 1000), tokens: { ...example.tokens }, serviceTier: example.tier, isUSOnly: false, serviceTierReported: true, estimatedDuration: 16 + event, estimatedFirstToken: 1.2, cost: example.detail.total })
    }
  }
  for (let i = 0; i < 18; i++) {
    const base = records[i]!
    const unknown = i % 3 === 0, incomplete = i % 3 === 2
    records.push({ ...base, id: `preview-antigravity-${i}`, service: 'antigravity', session: `antigravity-sample-${Math.floor(i / 3)}`, model: unknown ? 'unknown' : 'gemini-3.8-flash', tokens: { input: 2100, output: incomplete ? 0 : 1200, cached: 8400, cacheWrite: 0, cacheWriteLong: 0, inputReported: true, outputReported: !incomplete, cachedReported: true, cacheWriteReported: true }, serviceTier: 'unknown', serviceTierReported: false, cost: unknown || incomplete ? null : '0.006705' })
  }
  state.usage = { records, projectRoots: {}, sessionTitles, warnings: [], scannedAt: now, fileCount: 312, refreshing: false, source: '离线示例日志' }
  state.quota.windows = [{ id: 'codex:primary:300', bucket: 'codex', name: 'Codex', usedPercent: 28, durationMinutes: 300, resetsAt: now + 12700, label: null }, { id: 'codex:secondary:10080', bucket: 'codex', name: 'Codex', usedPercent: 63, durationMinutes: 10080, resetsAt: now + 276000, label: null }]
  for (const window of state.quota.windows) state.quota.history[window.id] = { window, points: Array.from({ length: 32 }, (_, index) => ({ date: now - (31 - index) * 900, usedPercent: index < 12 ? Math.min(100, 60 + index * 5) : Math.max(0, window.usedPercent - (31 - index) * .7), segment: index < 12 ? 1 : 2 })).filter((_, index) => index < 12 || index >= 16) }
  state.settings.antigravityEnabled = true
  state.antigravity = {
    groups: [
      { name: 'Gemini Models', buckets: [
        { id: 'gemini-5h', name: 'Five Hour Limit Remaining', window: '5h', remainingPercent: 76, resetsAt: now + 10800, disabled: false },
        { id: 'gemini-weekly', name: 'Weekly Limit Remaining', window: 'weekly', remainingPercent: 42, resetsAt: now + 250000, disabled: false },
      ] },
      { name: 'Claude and GPT models', buckets: [
        { id: '3p-5h', name: 'Five Hour Limit Remaining', window: '5h', remainingPercent: 0, resetsAt: now + 3000, disabled: false },
        { id: '3p-weekly', name: 'Weekly Limit Remaining', window: 'weekly', remainingPercent: 18, resetsAt: now + 500000, disabled: false },
      ] },
      { name: 'Gemini 4 Argon', buckets: [
        { id: 'gemini-argon-wtu-weekly', name: 'Gemini 4 Argon Weekly Limit', window: 'weekly', remainingPercent: 53, resetsAt: now + 100000, disabled: false },
      ] },
      { name: '新增分组（离线示例）', buckets: [
        { id: 'preview-unreported', name: '未报告窗口类型', window: null, remainingPercent: null, resetsAt: null, disabled: false },
      ] },
    ], error: null, lastSuccess: now, refreshing: false, requiresAction: false,
  }
  state.quota.lastSuccess = now
  state.quota.resetCredits = { availableCount: 3, credits: [2400, 64800, 360000].map((remaining, index) => ({ id: `sample-credit-${index}`, resetType: 'codexRateLimits', status: 'available', expiresAt: now + remaining })) }
  state.prices = Object.values(officialPrices)
  state.prices.push({ model: 'unknown', service: 'antigravity', rates: { input: null, output: null, cached: null, cacheWrite: null, cacheWriteLong: null }, contextThreshold: null, longContextRates: null, fastMultiplier: null, ultrafastMultiplier: null })
  // Explicit offline scenes exercise the displayed states without starting a local CLI.
  const quotaScene = new URLSearchParams(location.search).get('quota')
  if (quotaScene === 'stale') {
    state.quota.error = 'Codex 网络连接失败，请检查网络。60 秒后重试。'
    state.quota.lastSuccess = now - 600
  } else if (quotaScene === 'refreshing') state.quota.refreshing = true
  const antigravityScene = new URLSearchParams(location.search).get('antigravity')
  if (antigravityScene === 'weekly-only') {
    state.antigravity.groups = state.antigravity.groups.slice(0, 2).map(group => ({ ...group, buckets: group.buckets.filter(bucket => bucket.window === 'weekly') }))
  } else if (antigravityScene === 'stale') {
    state.antigravity.error = 'Antigravity 网络连接失败，请检查网络。60 秒后重试。'
    state.antigravity.lastSuccess = now - 600
  } else if (antigravityScene === 'refreshing') state.antigravity.refreshing = true
  else if (['empty', 'disabled', 'missing-cli', 'initial-loading'].includes(antigravityScene ?? '')) {
    state.settings.antigravityEnabled = antigravityScene !== 'disabled'
    state.antigravity = {
      groups: [], lastSuccess: null,
      error: antigravityScene === 'missing-cli' ? '未找到 Antigravity CLI。请先安装并登录 agy；自定义位置可通过 CODEX_QUOTA_AGY 指定。' : null,
      refreshing: antigravityScene === 'initial-loading', requiresAction: antigravityScene === 'missing-cli',
    }
  }
  state.priceDate = '离线示例'
  return state
}
