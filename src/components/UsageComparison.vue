<script setup lang="ts">
import { computed } from 'vue'
import AnimatedNumber from './AnimatedNumber.vue'

const props = defineProps<{ current: number; previous: number; kind: 'tokens' | 'money' }>()
const delta = computed(() => props.current - props.previous)
</script>

<template>
  <span class="summary-change" :data-direction="delta > 0 ? 'increase' : delta < 0 ? 'decrease' : undefined">
    <template v-if="delta === 0">较上期持平</template>
    <template v-else>
      <AnimatedNumber :value="Math.abs(delta)" :kind :prefix="delta > 0 ? '+' : '−'" :suffix="kind === 'tokens' ? ' Tokens' : undefined" /><template v-if="previous">（<AnimatedNumber :value="Math.abs(delta) / previous" kind="rate" />）</template>
    </template>
  </span>
</template>
