<script setup lang="ts">
import { computed } from 'vue'
import { countdown } from '@/lib/usage'

const props = defineProps<{ resetsAt: number | null; now: number }>()
const text = computed(() => countdown(props.resetsAt, props.now))
</script>

<template>
  <span v-if="text" class="deadline-countdown">
    <span v-for="(part, index) in text.split(/(\d+)/)" :key="index" :class="{ 'deadline-number': index % 2 === 1 }">{{ part }}</span>
  </span>
</template>
