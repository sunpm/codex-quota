<script setup lang="ts">
import { onBeforeUnmount, onMounted, watch, useTemplateRef } from 'vue'
import { init, use, type EChartsCoreOption } from 'echarts/core'
import { BarChart, LineChart, HeatmapChart } from 'echarts/charts'
import { GridComponent, TooltipComponent, LegendComponent, CalendarComponent, VisualMapComponent, AriaComponent } from 'echarts/components'
import { CanvasRenderer } from 'echarts/renderers'
import type { ECElementEvent, EChartsType } from 'echarts/core'
import type { ChartTimeHover } from '@/types'

use([BarChart, LineChart, HeatmapChart, GridComponent, TooltipComponent, LegendComponent, CalendarComponent, VisualMapComponent, AriaComponent, CanvasRenderer])
const props = defineProps<{ option: EChartsCoreOption; label: string; height?: number; animations?: boolean; timeHover?: boolean }>()
const emit = defineEmits<{ timeHover: [value: ChartTimeHover | null]; select: [dataIndex: number] }>()
const element = useTemplateRef('chartElement')
let chart: EChartsType | undefined
let observer: ResizeObserver | undefined
const theme = window.matchMedia('(prefers-color-scheme: dark)')
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)')
function render() {
  if (!chart || !element.value) return
  if (props.timeHover) emit('timeHover', null)
  const styles = getComputedStyle(element.value)
  chart.setOption({
    backgroundColor: 'transparent',
    animation: props.animations !== false && !reducedMotion.matches,
    animationDuration: 220,
    textStyle: { fontFamily: 'system-ui, sans-serif', color: styles.getPropertyValue('--chart-text').trim(), fontSize: 12 },
    color: ['#3279bd', '#448d86', '#ad8044', '#9e6686'],
    aria: { enabled: true, decal: { show: false }, label: { description: props.label } },
    ...props.option,
  }, { notMerge: true })
}
function applyTheme() {
  chart?.dispose()
  chart = init(element.value!, theme.matches ? 'dark' : undefined, { renderer: 'canvas' })
  chart.on('click', 'series', (event: ECElementEvent) => emit('select', event.dataIndex))
  if (props.timeHover) {
    chart.getZr().on('mousemove', event => {
      const { offsetX: x, offsetY: y } = event
      if (!chart!.containPixel({ gridIndex: 0 }, [x, y])) { emit('timeHover', null); return }
      const timestamp = chart!.convertFromPixel({ xAxisIndex: 0 }, x) as number
      const nearby = chart!.convertFromPixel({ xAxisIndex: 0 }, x + 12) as number
      emit('timeHover', { timestamp, tolerance: Math.abs(nearby - timestamp) })
    })
    chart.getZr().on('globalout', () => emit('timeHover', null))
  }
  render()
}
onMounted(() => {
  applyTheme()
  observer = new ResizeObserver(() => chart?.resize())
  observer.observe(element.value!)
  theme.addEventListener('change', applyTheme)
  reducedMotion.addEventListener('change', render)
  render()
})
watch(() => [props.option, props.animations], render)
onBeforeUnmount(() => { observer?.disconnect(); chart?.dispose(); theme.removeEventListener('change', applyTheme); reducedMotion.removeEventListener('change', render) })
</script>
<template><div ref="chartElement" class="chart" :style="{ height: `${height ?? 210}px` }" role="img" :aria-label="label" /></template>
