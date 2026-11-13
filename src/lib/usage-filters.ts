import { computed, ref, watch } from 'vue'
import { toRefs, useLocalStorage } from '@vueuse/core'
import { isPlainObject, isString } from '@pmun/utils'
import type { Metric, Page, QuotaService, UsageService } from '@/types'
import type { SortDirection } from './table'
import { dateTimeKey, dayKey, shiftDay, startOfDay } from './usage'

export const usageRanges = [{ value: 'today', label: '今天' }, { value: 'yesterday', label: '昨天' }, { value: '24h', label: '最近 24 小时' }, { value: '7', label: '7 天' }, { value: '30', label: '30 天' }, { value: 'all', label: '全部' }, { value: 'custom', label: '自定义' }] as const

export type UsageSort = Metric | 'last' | 'count' | 'hitRate'
interface UsageFilters {
  view: 'record' | 'session' | 'project'
  period: typeof usageRanges[number]['value']
  metric: Metric
  sort: UsageSort
  direction: SortDirection
  model: string
  search: string
  start: string
  end: string
}

export function parseUsageDateTime(value: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) return null
  const date = new Date(value)
  return Number.isFinite(date.getTime()) && dateTimeKey(date) === value ? date.getTime() / 1000 : null
}

function storedDateTime(value: unknown, fallback: string, end = false) {
  if (!isString(value)) return fallback
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const date = new Date(`${value}T00:00:00`)
    if (dayKey(date) !== value) return fallback
    // Old date-only ranges included the entire end day.
    return dateTimeKey(end ? shiftDay(date, 1) : date)
  }
  return parseUsageDateTime(value) !== null ? value : fallback
}

function readFilters(raw: string, defaults: UsageFilters): UsageFilters {
  const parsed: unknown = JSON.parse(raw)
  if (!isPlainObject(parsed)) return { ...defaults }
  const saved: Record<string, unknown> = parsed
  const start = storedDateTime(saved.start, defaults.start)
  const end = storedDateTime(saved.end, defaults.end, true)
  return {
    view: saved.view === 'project' || saved.view === 'record' ? saved.view : 'session',
    period: usageRanges.find(range => range.value === saved.period)?.value ?? defaults.period,
    metric: saved.metric === 'cost' ? 'cost' : 'tokens',
    sort: (['tokens', 'cost', 'last', 'count', 'hitRate'] as const).find(key => key === saved.sort) ?? (saved.metric === 'cost' ? 'cost' : 'tokens'),
    direction: saved.direction === 'asc' ? 'asc' : 'desc',
    model: isString(saved.model) && saved.model ? saved.model : defaults.model,
    search: isString(saved.search) ? saved.search : defaults.search,
    start: start < end ? start : defaults.start,
    end: start < end ? end : defaults.end,
  }
}

function defaultFilters(): UsageFilters {
  const today = startOfDay(new Date())
  return { view: 'session', period: '7', metric: 'tokens', sort: 'tokens', direction: 'desc', model: 'all', search: '', start: dateTimeKey(shiftDay(today, -6)), end: dateTimeKey(shiftDay(today, 1)) }
}

const initialDefaults = defaultFilters()
const options = { writeDefaults: false, serializer: { read: (raw: string) => readFilters(raw, defaultFilters()), write: JSON.stringify } }
// Retain the original session preferences as the shared detail filters.
const details = useLocalStorage('usage.filters.sessions.v1', { ...initialDefaults }, options)
const overview = ref<UsageFilters>({ ...initialDefaults })
export const usageService = useLocalStorage<UsageService | 'all'>('usage.service.v1', 'all', {
  serializer: { read: value => value === 'codex' || value === 'antigravity' ? value : 'all', write: value => value },
})
export const quotaService = useLocalStorage<QuotaService>('quota.service.v1', 'all', {
  serializer: { read: value => value === 'codex' || value === 'antigravity' ? value : 'all', write: value => value },
})
watch(usageService, () => { details.value.model = 'all'; overview.value.model = 'all' })
export const overviewGroupBy = ref<'model' | 'project' | 'session'>('model')

export function syncOverviewToDetails(view: 'session' | 'project' = 'session') {
  details.value = { ...overview.value, view, search: '' }
}

export function useUsageFilters(page: () => Page) {
  const current = computed({
    get: () => page() === 'details' ? details.value : overview.value,
    set: (value: UsageFilters) => {
      if (page() === 'details') details.value = value
      else overview.value = value
    },
  })
  return toRefs(current)
}
