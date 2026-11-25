<script setup lang="ts">
import { computed, inject, type Ref } from 'vue'
import NumberFlow from '@number-flow/vue'
import { numberOptions, type NumberStyle } from '@/lib/number-format'

const props = withDefaults(defineProps<{
  value: number | null
  kind?: NumberStyle
  suffix?: string
  empty?: string
}>(), { kind: 'number', empty: '—' })
const animate = inject<Ref<boolean>>('numberAnimations')
const format = computed(() => numberOptions(props.kind, props.value ?? 0))
const timing = { duration: 240, easing: 'ease-out' }
</script>

<template>
  <span v-if="value === null">{{ empty }}</span>
  <NumberFlow v-else-if="animate" :value :format locales="en-US" :suffix
    :transform-timing="timing" :opacity-timing="timing" />
  <span v-else>{{ value.toLocaleString('en-US', format) }}{{ suffix }}</span>
</template>
