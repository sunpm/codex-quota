<script setup lang="ts">
import { computed } from 'vue'
import { countdown } from '@/lib/usage'

const props = defineProps<{ resetsAt: number | null; now: number }>()
const remaining = computed(() => countdown(props.resetsAt, props.now))
</script>

<template>
  <span v-if="remaining" class="deadline-countdown">
    <template v-if="typeof remaining === 'string'">{{ remaining }}</template>
    <template v-else>
      <span v-for="part in remaining" :key="part.unit" class="deadline-part"><strong class="deadline-number">{{ part.padded ? String(part.value).padStart(2, '0') : part.value }}</strong> {{ part.unit }}</span>
    </template>
  </span>
</template>
