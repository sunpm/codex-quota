<script setup lang="ts">
import { computed } from 'vue'
import { money, percent, shortTokens } from '@/lib/usage'

const props = defineProps<{ current: number; previous: number; kind: 'tokens' | 'money' }>()
const delta = computed(() => props.current - props.previous)
const amount = computed(() => props.kind === 'tokens' ? `${shortTokens(Math.abs(delta.value))} Tokens` : money(Math.abs(delta.value)))
</script>

<template>
  <span class="summary-change" :data-direction="delta > 0 ? 'increase' : delta < 0 ? 'decrease' : undefined">
    <template v-if="delta === 0">较上期持平</template>
    <template v-else>
      {{ delta > 0 ? '+' : '−' }}{{ amount }}<template v-if="previous">（{{ percent(Math.abs(delta) / previous) }}）</template>
    </template>
  </span>
</template>
