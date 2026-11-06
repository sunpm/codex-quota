<script setup lang="ts">
import { onMounted, ref, useTemplateRef, watch } from 'vue'
import { useResizeObserver } from '@vueuse/core'

const props = withDefaults(defineProps<{ selection: string | number; as?: 'div' | 'nav' }>(), { as: 'div' })
const items = useTemplateRef<HTMLElement>('items')
const clipPath = ref('')
const columns = ref('')

function measureSelection() {
  const container = items.value
  const selected = container?.querySelector<HTMLElement>('[data-selected="true"]')
  if (!container || !selected) return
  const bounds = container.getBoundingClientRect()
  const active = selected.getBoundingClientRect()
  clipPath.value = `inset(${active.top - bounds.top}px ${bounds.right - active.right}px ${bounds.bottom - active.bottom}px ${active.left - bounds.left}px round var(--selection-radius))`
  // Match the original cells so highlighted text can change weight without moving the layout.
  columns.value = props.as === 'nav' ? '1fr' : Array.from(container.children, item => `${item.getBoundingClientRect().width}px`).join(' ')
}

onMounted(measureSelection)
watch(() => props.selection, measureSelection, { flush: 'post' })
useResizeObserver(items, measureSelection)
</script>

<template>
  <component :is="as" class="sliding-selection" :class="{ 'selection-ready': clipPath }">
    <div ref="items" class="selection-items"><slot :highlight="false" /></div>
    <!-- The highlighted slot contains only presentation elements, never duplicate controls. -->
    <div v-if="clipPath" class="selection-items selection-highlight" :style="{ clipPath, gridTemplateColumns: columns }" aria-hidden="true" inert>
      <slot :highlight="true" />
    </div>
  </component>
</template>
