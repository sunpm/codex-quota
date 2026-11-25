import { addDays, formatDate, startOf, trimDecimalZeros } from '@pmun/utils'
import type { UsageRecord, Metric, CostComponent, QuotaSeries } from '@/types'
import { numberOptions } from './number-format'

export const serviceName = (service: string) => service === 'codex' ? 'Codex' : service === 'antigravity' ? 'Antigravity' : '全部服务'
export const knownTokens = (record: UsageRecord) => record.tokens.inputReported !== false && record.tokens.outputReported !== false && record.tokens.cachedReported !== false

export function reportedTokenCount(record: UsageRecord, kind: CostComponent['kind']): number | null {
  const reported = kind === 'cacheWrite' || kind === 'cacheWriteLong'
    ? record.tokens.cacheWriteReported === true || record.tokens.cacheWrite > 0
    : record.tokens[`${kind}Reported`] !== false
  return reported ? record.tokens[kind] : null
}
export const tokenCount = (record: UsageRecord) => record.tokens.input + record.tokens.output + record.tokens.cached + record.tokens.cacheWrite
export const shortTokens = (value: number) => value.toLocaleString('en-US', numberOptions('tokens', value))
export const dateText = (seconds: number | null | undefined, full = false) => seconds == null ? '—' : new Date(seconds * 1000).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', ...(full ? { year: 'numeric', second: '2-digit' } : {}) })
export const dayKey = (date: Date) => formatDate(date, 'YYYY-MM-DD')
export function dateTimeKey(date: Date, precise = false) {
  let value = `${dayKey(date)}T${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
  if (precise && (date.getSeconds() || date.getMilliseconds())) {
    value += `:${String(date.getSeconds()).padStart(2, '0')}`
    if (date.getMilliseconds()) value += `.${String(date.getMilliseconds()).padStart(3, '0')}`
  }
  return value
}
export const startOfDay = (date: Date) => startOf(date, 'day')
export const shiftDay = (date: Date, days: number) => addDays(date, days)
export const basename = (path: string) => path.split(/[\\/]/).filter(Boolean).at(-1) || '未知项目'

// Rust Decimal has at most 28 fractional digits; aggregation keeps that precision until display.
const decimalScale = 10n ** 28n
export function sumCosts(records: UsageRecord[]) {
  const amount = records.reduce((sum, record) => {
    if (record.cost == null) return sum
    const [whole = '0', fraction = ''] = record.cost.split('.')
    return sum + BigInt(whole) * decimalScale + BigInt(fraction.padEnd(28, '0'))
  }, 0n)
  return `${amount / decimalScale}.${String(amount % decimalScale).padStart(28, '0')}`
}
export interface Summary { tokens: number; input: number; output: number; cached: number; cacheWrite: number; count: number; sessions: number; amount: string; priced: number; unpriced: number; hitRate: number | null; incomplete: number; inputKnown: boolean; outputKnown: boolean; cachedKnown: boolean; cacheWriteKnown: boolean }
export function summarize(records: UsageRecord[]): Summary {
  const result: Summary = { tokens: 0, input: 0, output: 0, cached: 0, cacheWrite: 0, count: records.length, sessions: new Set(records.map(record => `${record.service}:${record.session}`)).size, amount: sumCosts(records), priced: 0, unpriced: 0, hitRate: null, incomplete: 0, inputKnown: records.every(record => record.tokens.inputReported !== false), outputKnown: records.every(record => record.tokens.outputReported !== false), cachedKnown: records.every(record => record.tokens.cachedReported !== false), cacheWriteKnown: records.length > 0 && records.every(record => record.tokens.cacheWriteReported || record.tokens.cacheWrite > 0) }
  for (const record of records) {
    result.tokens += tokenCount(record); result.input += record.tokens.input; result.output += record.tokens.output
    result.cached += record.tokens.cached; result.cacheWrite += record.tokens.cacheWrite
    if (!knownTokens(record)) result.incomplete++
    if (record.cost == null) result.unpriced++; else result.priced++
  }
  const incoming = result.input + result.cached + result.cacheWrite
  result.hitRate = incoming && !result.incomplete ? result.cached / incoming : null
  return result
}
export const costLabel = (_summary?: Summary) => '估算费用'
export const costColumnLabel = (_summary?: Summary) => '估算费用'
export function money(amount: string | number | null) {
  if (amount === null) return '未定价'
  const value = Number(amount)
  return value.toLocaleString('en-US', numberOptions('money', value))
}
export const summaryAmount = (summary: Summary) => summary.count && !summary.priced ? null : Number(summary.amount)
export const summaryMoney = (summary: Summary) => money(summaryAmount(summary))
export const exactMoney = (amount: string | null) => amount == null ? '未定价' : `$${trimDecimalZeros(amount)}`
export const costTooltip = (summary: Summary) => summary.count && !summary.priced ? '未定价' : exactMoney(summary.amount)
export const costCardTitle = (_summary?: Summary) => 'API 等价估算，非订阅账单。'
export function compareSummaries(a: Summary, b: Summary, metric: Metric) {
  if (metric === 'tokens') return b.tokens - a.tokens
  const aCost = Number(a.amount), bCost = Number(b.amount)
  if (aCost !== bCost) return bCost - aCost
  if ((a.unpriced > 0) !== (b.unpriced > 0)) return a.unpriced > 0 ? -1 : 1
  return b.tokens - a.tokens
}
export function billingTier(record: UsageRecord) {
  switch (record.serviceTier.toLowerCase()) {
    case 'standard': case 'default': case 'auto': return 'Standard'
    case 'fast': case 'priority': return 'Fast'
    case 'ultrafast': return 'Ultrafast'
    default: return '未知档位'
  }
}
export const billingTierLabel = (record: UsageRecord) => `${billingTier(record) === '未知档位' ? `${record.serviceTier || '未知'}（未知档位）` : billingTier(record)}${billingTier(record) === 'Standard' && record.serviceTierReported !== true ? '（估算）' : ''}`
export const metricValue = (summary: Summary, metric: Metric) => metric === 'tokens' ? summary.tokens : Number(summary.amount)
export function metricShare(part: Summary, whole: Summary, metric: Metric) {
  const denominator = metricValue(whole, metric)
  return denominator && (metric === 'tokens' || part.priced) ? metricValue(part, metric) / denominator : null
}
export const percent = (value: number | null) => value == null ? '—' : value.toLocaleString('en-US', numberOptions('rate', value))
type CountdownPart = { value: number; unit: string; padded?: boolean }
export function countdown(resetsAt: number | null, now: number): string | CountdownPart[] {
  if (resetsAt == null) return '重置时间未知'
  const remaining = Math.max(0, Math.ceil(resetsAt - now))
  if (!remaining) return '等待实际重置'
  if (remaining > 7 * 86400) return ''
  const days = Math.floor(remaining / 86400)
  const hours = Math.floor(remaining / 3600)
  const minutes = Math.floor(remaining / 60)
  const seconds = remaining % 60
  if (remaining > 86400) return [{ value: days, unit: '天' }, { value: hours % 24, unit: '小时' }]
  if (remaining > 3600) return [{ value: hours, unit: '小时' }, { value: minutes % 60, unit: '分', padded: true }]
  const secondPart = { value: seconds, unit: '秒', padded: true }
  return minutes ? [{ value: minutes, unit: '分' }, secondPart] : [secondPart]
}
export function countdownTickMs(deadlines: (number | null | undefined)[], now: number) {
  let delay = Infinity
  for (const deadline of deadlines) {
    if (deadline == null) continue
    const remaining = Math.ceil(deadline - now)
    if (remaining <= 0) continue
    if (remaining <= 3600) return 1000
    if (remaining <= 86400) delay = Math.min(delay, Math.min(60, remaining - 3600, remaining % 60 || 60) * 1000)
    else if (remaining <= 7 * 86400) delay = Math.min(delay, Math.min(3600, remaining - 86400, remaining % 3600 || 3600) * 1000)
    else delay = Math.min(delay, Math.min(86400, remaining - 7 * 86400) * 1000)
  }
  return Number.isFinite(delay) ? Math.max(1000, delay) : null
}
export const quotaLabel = (minutes: number | null, label: string | null) => label ?? (minutes ? minutes % 1440 === 0 ? `${minutes / 1440} 天额度` : minutes % 60 === 0 ? `${minutes / 60} 小时额度` : `${minutes} 分钟额度` : '额度')

export function dailyQuotaUsage({ points }: QuotaSeries, midnight: number): string {
  const first = points.findIndex(point => point.date >= midnight)
  if (first < 0) return '—'

  let used = 0
  let complete = points[first].date === midnight
  for (let i = first; i < points.length; i++) {
    const point = points[i]
    const previous = points[i - 1]
    if (!previous) continue
    const increase = point.usedPercent - previous.usedPercent
    const sameCycle = point.segment === previous.segment ||
      (point.resetsAt !== undefined && point.resetsAt === previous.resetsAt && increase >= 0)
    if (sameCycle) {
      if (previous.date >= midnight) used += increase
      // 跨零点的增量无法按日拆分，只有持平的读数能确定零点基线。
      else if (increase === 0) complete = true
      continue
    }

    if (previous.date >= midnight) complete = false
    if (previous.resetsAt !== undefined && point.resetsAt !== undefined &&
        previous.resetsAt >= midnight && previous.resetsAt <= point.date && point.resetsAt > previous.resetsAt) {
      used += point.usedPercent
    } else if (previous.date >= midnight) {
      used += Math.max(0, increase)
    }
  }
  if (complete) return `${used.toLocaleString('zh-CN', { maximumFractionDigits: 1 })}%`
  if (used === 0) return '—'
  return used < 0.1 ? '>0%' : `≥${Math.floor(used * 10) / 10}%`
}
