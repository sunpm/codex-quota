<script setup lang="ts">
import { computed } from 'vue'
import { ChevronDown } from '@lucide/vue'
import { changeSettings } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Checkbox } from '@/components/ui/checkbox'
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'

const props = defineProps<{ selected: string[] }>()
const columns = [{ value: 'speed', label: '速度' }, { value: 'firstToken', label: '首字' }, { value: 'cacheWrite', label: '缓存写入' }, { value: 'billingTier', label: '计费档位' }]
const label = computed(() => columns.filter(item => props.selected.includes(item.value)).map(item => item.label).join('、') || '不显示')
function select(value: string, checked: boolean | 'indeterminate') {
  const selected = props.selected.filter(item => item !== value)
  if (checked === true) selected.push(value)
  void changeSettings({ detailColumns: selected })
}
</script>

<template>
  <Popover><PopoverTrigger as-child><Button variant="outline" size="sm" :aria-label="`明细可选列：${label}`">{{ label }}<ChevronDown aria-hidden="true" /></Button></PopoverTrigger><PopoverContent class="choices-popover" align="end"><label v-for="item in columns" :key="item.value" class="checkbox-row"><Checkbox :model-value="selected.includes(item.value)" @update:model-value="select(item.value, $event)" />{{ item.label }}</label></PopoverContent></Popover>
</template>
