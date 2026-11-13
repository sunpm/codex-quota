import { computed, ref, watch, type Ref } from 'vue'
import { useLocalStorage } from '@vueuse/core'

export type SortDirection = 'asc' | 'desc'
export const tablePageSizes = [20, 50, 100]

export function compareTableNumbers(a: number | null, b: number | null, direction: SortDirection) {
  if (a === null) return b === null ? 0 : 1
  if (b === null) return -1
  return direction === 'asc' ? a - b : b - a
}

export function useTablePagination<T>(rows: Ref<T[]>, storageKey: string) {
  const page = ref(1)
  const pageSize = useLocalStorage(storageKey, 20, {
    serializer: {
      read: raw => tablePageSizes.find(size => size === Number(raw)) ?? 20,
      write: String,
    },
  })
  const pageCount = computed(() => Math.max(1, Math.ceil(rows.value.length / pageSize.value)))
  const pageRows = computed(() => rows.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value))
  watch(pageSize, () => { page.value = 1 }, { flush: 'sync' })
  watch(pageCount, count => { page.value = Math.min(page.value, count) }, { flush: 'sync' })
  return { page, pageSize, pageRows }
}
