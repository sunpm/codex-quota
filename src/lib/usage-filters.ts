import { computed, ref, watch } from 'vue'
import { toRefs, useLocalStorage } from '@vueuse/core'
import { isPlainObject, isString } from '@pmun/utils'
import type { Metric, Page, UsageService } from '@/types'
import { dayKey, shiftDay } from './usage'

export const usageRanges = [{ value: 'today', label: '今天' }, { value: 'yesterday', label: '昨天' }, { value: '7', label: '7 天' }, { value: '30', label: '30 天' }, { value: 'all', label: '全部' }, { value: 'custom', label: '自定义' }] as const

interface UsageFilters {
  view: 'session' | 'project'
  period: typeof usageRanges[number]['value']
  metric: Metric
  model: string
  search: string
  start: string
  end: string
}

function storedDate(value: unknown, fallback: string) {
  return isString(value) && /^\d{4}-\d{2}-\d{2}$/.test(value) && dayKey(new Date(`${value}T00:00:00`)) === value ? value : fallback
}

function readFilters(raw: string, defaults: UsageFilters): UsageFilters {
  const parsed: unknown = JSON.parse(raw)
  if (!isPlainObject(parsed)) return { ...defaults }
  const saved: Record<string, unknown> = parsed
  const start = storedDate(saved.start, defaults.start)
  const end = storedDate(saved.end, defaults.end)
  return {
    view: saved.view === 'project' ? 'project' : 'session',
    period: usageRanges.find(range => range.value === saved.period)?.value ?? defaults.period,
    metric: saved.metric === 'cost' ? 'cost' : 'tokens',
    model: isString(saved.model) && saved.model ? saved.model : defaults.model,
    search: isString(saved.search) ? saved.search : defaults.search,
    start: start <= end ? start : defaults.start,
    end: start <= end ? end : defaults.end,
  }
}

function defaultFilters(): UsageFilters {
  return { view: 'session', period: '7', metric: 'tokens', model: 'all', search: '', start: dayKey(shiftDay(new Date(), -6)), end: dayKey(new Date()) }
}

const initialDefaults = defaultFilters()
const options = { writeDefaults: false, serializer: { read: (raw: string) => readFilters(raw, defaultFilters()), write: JSON.stringify } }
// Retain the original session preferences as the shared detail filters.
const details = useLocalStorage('usage.filters.sessions.v1', { ...initialDefaults }, options)
const overview = ref<UsageFilters>({ ...initialDefaults })
export const usageService = useLocalStorage<UsageService | 'all'>('usage.service.v1', 'all', {
  serializer: { read: value => value === 'codex' || value === 'antigravity' ? value : 'all', write: value => value },
})
watch(usageService, () => { details.value.model = 'all'; overview.value.model = 'all' })
export const overviewGroupBy = ref<'model' | 'project'>('model')

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
