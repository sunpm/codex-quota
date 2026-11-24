<script setup lang="ts">
import { RefreshCw } from '@lucide/vue'
import type { AppSnapshot } from '@/types'
import { execute } from '@/lib/app'
import { dateText } from '@/lib/usage'
import { Button } from '@/components/ui/button'
import DeadlineCountdown from './DeadlineCountdown.vue'
import AnimatedNumber from './AnimatedNumber.vue'
import antigravityIcon from '@/assets/antigravity.svg'

defineProps<{ state: AppSnapshot; now: number }>()
const windowLabel = (window: string | null) => window === '5h' ? '五小时额度' : window === 'weekly' ? '周额度' : '额度'
const tone = (remaining: number | null) => remaining === null ? 'unknown' : remaining <= 0 ? 'exhausted' : remaining <= 20 ? 'warning' : 'normal'
const timeLabels = { ide: '上次观察到变化', desktop: '上次读取面板', cli: '上次读取' }
</script>

<template>
  <section class="surface antigravity-surface" aria-labelledby="antigravity-heading">
    <div class="section-heading">
      <div class="service-title-group">
        <img class="service-icon" :src="antigravityIcon" alt="" aria-hidden="true" />
        <h2 id="antigravity-heading">Antigravity</h2>
      </div>
      <div class="setting-actions">
        <span>剩余</span>
        <Button variant="outline" size="sm" :disabled="!state.settings.antigravityEnabled || state.antigravity.refreshing" @click="execute('refresh_antigravity')">
          <RefreshCw :size="14" :class="{ spinning: state.antigravity.refreshing }" />{{ state.antigravity.refreshing ? '读取中…' : '刷新' }}
        </Button>
      </div>
    </div>
    <p v-if="!state.settings.antigravityEnabled" class="notice">Antigravity 监测已关闭，可在设置中开启。</p>
    <p v-if="state.antigravity.error" class="notice warning" role="status">{{ state.antigravity.error }}<span v-if="state.antigravity.groups.length"> 上次读数已过期。</span></p>
    <div v-if="!state.antigravity.groups.length && !state.antigravity.error" class="empty-state">{{ state.antigravity.refreshing ? '正在读取 Antigravity 额度…' : '暂无额度数据' }}</div>
    <div v-if="state.antigravity.groups.length" class="antigravity-groups" :class="{ 'single-bucket-groups': state.antigravity.groups.every(group => group.buckets.length === 1) }">
      <div v-for="(group, index) in state.antigravity.groups" :key="index" class="antigravity-group">
        <h3 class="antigravity-group-title">{{ group.name }}</h3>
        <div class="quota-windows-grid">
          <div v-for="bucket in group.buckets" :key="bucket.id" class="quota-window" :class="tone(bucket.remainingPercent)" :title="`额度桶：${bucket.id}`">
            <div class="quota-label-row">
              <div>
                <h4>{{ windowLabel(bucket.window) }}</h4>
                <small>{{ bucket.name }}</small>
              </div>
              <strong><AnimatedNumber :value="bucket.disabled || bucket.remainingPercent === null ? null : Math.floor(bucket.remainingPercent)" :empty="bucket.disabled ? '未启用' : '未知'" suffix="%" /></strong>
            </div>
            <div v-if="bucket.remainingPercent !== null" class="quota-track" aria-hidden="true">
              <div :style="{ width: `${bucket.remainingPercent}%` }" />
            </div>
            <div class="quota-time-row">
              <DeadlineCountdown :resets-at="bucket.resetsAt" :now="now" />
              <span v-if="bucket.resetsAt !== null" class="muted">重置 · {{ dateText(bucket.resetsAt) }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
    <div v-if="state.antigravity.lastSuccess !== null" class="antigravity-footer muted">
      {{ timeLabels[state.settings.antigravitySource] }} · {{ dateText(state.antigravity.lastSuccess, true) }}
    </div>
  </section>
</template>

<style scoped>
.antigravity-groups { display: grid; gap: 20px; margin-top: 20px; }
.antigravity-group { min-width: 0; }
.antigravity-group + .antigravity-group { border-top: 1px solid color-mix(in srgb, var(--border) 60%, transparent); padding-top: 18px; }
.antigravity-group:only-child, .quota-window:only-child { grid-column: 1 / -1; }
@media (min-width: 821px) {
  .single-bucket-groups { grid-template-columns: repeat(2, minmax(0, 1fr)); column-gap: 24px; }
  .single-bucket-groups > .antigravity-group + .antigravity-group { border-top: 0; padding-top: 0; }
}
.antigravity-group-title { font-size: 13px; font-weight: 500; color: var(--foreground); margin-bottom: 10px; }
.quota-label-row > div { min-width: 0; overflow-wrap: anywhere; }
.unknown { --quota-color: var(--muted); }
.antigravity-footer { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 8px 20px; font-size: 12px; margin-top: 22px; }
</style>
