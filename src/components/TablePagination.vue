<script setup lang="ts">
import { computed } from 'vue'
import { ChevronLeft, ChevronRight } from '@lucide/vue'
import { tablePageSizes } from '@/lib/table'
import { Button } from '@/components/ui/button'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'

const props = defineProps<{ page: number; pageSize: number; total: number }>()
const emit = defineEmits<{ 'update:page': [value: number]; 'update:pageSize': [value: number] }>()
const pageCount = computed(() => Math.max(1, Math.ceil(props.total / props.pageSize)))
function jump(event: Event) {
  const input = event.currentTarget as HTMLInputElement
  const value = input.valueAsNumber
  const page = Number.isInteger(value) ? Math.min(pageCount.value, Math.max(1, value)) : props.page
  emit('update:page', page)
  input.value = String(page)
}
</script>

<template>
  <div v-if="total" class="table-pagination">
    <span class="muted">共 {{ total.toLocaleString('zh-CN') }} 条</span>
    <NativeSelect :model-value="pageSize" aria-label="每页条数" @change="emit('update:pageSize', Number(($event.target as HTMLSelectElement).value))"><NativeSelectOption v-for="size in tablePageSizes" :key="size" :value="size">{{ size }} 条 / 页</NativeSelectOption></NativeSelect>
    <nav aria-label="表格分页">
      <Button variant="ghost" size="sm" aria-label="上一页" :disabled="page <= 1" @click="emit('update:page', page - 1)"><ChevronLeft /></Button>
      <input :value="page" type="number" min="1" :max="pageCount" step="1" aria-label="页码" @change="jump" @keydown.enter.prevent="jump" @keydown.esc="($event.currentTarget as HTMLInputElement).value = String(page)" />
      <span>/ {{ pageCount.toLocaleString('zh-CN') }} 页</span>
      <Button variant="ghost" size="sm" aria-label="下一页" :disabled="page >= pageCount" @click="emit('update:page', page + 1)"><ChevronRight /></Button>
    </nav>
  </div>
</template>

<style scoped>
.table-pagination { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; flex-shrink: 0; padding: 10px 13px; border-top: 1px solid var(--border); font-size: 12px; font-variant-numeric: tabular-nums; }
nav { display: flex; align-items: center; gap: 6px; margin-left: auto; }
input[type=number] { width: 64px; height: 28px; padding: 3px 6px; border: 1px solid var(--input); border-radius: 6px; background: var(--card); color: var(--foreground); font-size: 12px; line-height: 20px; text-align: center; }
</style>
