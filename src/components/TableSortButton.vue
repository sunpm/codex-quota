<script setup lang="ts">
import { ArrowDown, ArrowUp, ArrowDownUp } from '@lucide/vue'
import type { SortDirection } from '@/lib/table'

defineProps<{ label: string; active: boolean; direction: SortDirection }>()
defineEmits<{ click: [] }>()
</script>

<template>
  <button class="table-sort" :title="label" :aria-label="`按${label}${active && direction === 'desc' ? '升序' : '降序'}排序`" @click="$emit('click')"><span>{{ label }}</span><component :is="active ? direction === 'asc' ? ArrowUp : ArrowDown : ArrowDownUp" :size="11" /></button>
</template>
