<script setup lang="ts">
import { ref, watch } from 'vue'
import { ChevronLeft, ChevronRight } from '@lucide/vue'
import { tablePageSizes } from '@/lib/table'
import { Input } from '@/components/ui/input'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import { Pagination, PaginationContent, PaginationNext, PaginationPrevious } from '@/components/ui/pagination'

const props = defineProps<{ page: number; pageSize: number; total: number }>()
const emit = defineEmits<{ 'update:page': [value: number]; 'update:pageSize': [value: number] }>()
const pageInput = ref<string | number>(props.page)
watch(() => props.page, page => { pageInput.value = page })
function jump(event: Event, pageCount: number) {
  const input = event.currentTarget as HTMLInputElement
  const value = input.valueAsNumber
  const page = Number.isInteger(value) ? Math.min(pageCount, Math.max(1, value)) : props.page
  emit('update:page', page)
  pageInput.value = page
}
</script>

<template>
  <div v-if="total" class="table-pagination">
    <span class="muted">共 {{ total.toLocaleString('zh-CN') }} 条</span>
    <NativeSelect :model-value="pageSize" aria-label="每页条数" @change="emit('update:pageSize', Number(($event.target as HTMLSelectElement).value))"><NativeSelectOption v-for="size in tablePageSizes" :key="size" :value="size">{{ size }} 条 / 页</NativeSelectOption></NativeSelect>
    <Pagination v-slot="{ pageCount }" class="table-page-navigation" data-size="sm" :page="page" :items-per-page="pageSize" :total="total" aria-label="表格分页" @update:page="emit('update:page', $event)">
      <PaginationContent class="pagination-controls">
        <PaginationPrevious size="sm" aria-label="上一页"><ChevronLeft /></PaginationPrevious>
        <div class="page-position">
          <Input v-model="pageInput" class="page-input shadow-none" type="number" min="1" :max="pageCount" step="1" aria-label="页码" @change="jump($event, pageCount)" @keydown.enter.prevent="jump($event, pageCount)" @keydown.esc="pageInput = page" />
          <span>/ {{ pageCount.toLocaleString('zh-CN') }} 页</span>
        </div>
        <PaginationNext size="sm" aria-label="下一页"><ChevronRight /></PaginationNext>
      </PaginationContent>
    </Pagination>
  </div>
</template>

<style scoped>
.table-pagination { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; flex-shrink: 0; padding: 10px 13px; border-top: 1px solid var(--border); font-size: 12px; font-variant-numeric: tabular-nums; }
.table-page-navigation { width: auto; margin-left: auto; margin-right: 0; }
.pagination-controls { gap: 8px; }
.page-position { display: flex; align-items: center; gap: 8px; white-space: nowrap; }
.page-input { width: 64px; flex-shrink: 0; height: 28px; padding: 3px 6px; font-size: 12px; line-height: 20px; text-align: center; }
</style>
