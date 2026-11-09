<script setup lang="ts">
import { RefreshCw } from '@lucide/vue'
import type { AppSnapshot } from '@/types'
import { execute } from '@/lib/app'
import { countdown, dateText } from '@/lib/usage'
import { Button } from '@/components/ui/button'

defineProps<{ state: AppSnapshot; now: number }>()
const windowLabel = (window: string | null) => window === '5h' ? '五小时额度' : window === 'weekly' ? '周额度' : '额度'
const tone = (remaining: number | null) => remaining === null ? 'unknown' : remaining <= 0 ? 'exhausted' : remaining <= 20 ? 'warning' : 'normal'
</script>

<template>
  <section class="surface antigravity-surface" aria-labelledby="antigravity-heading">
    <div class="section-heading">
      <h2 id="antigravity-heading">Antigravity</h2>
      <div class="setting-actions"><span>剩余</span><Button variant="outline" size="sm" :disabled="!state.settings.antigravityEnabled || state.antigravity.refreshing" @click="execute('refresh_antigravity')">
        <RefreshCw :size="14" :class="{ spinning: state.antigravity.refreshing }" />{{ state.antigravity.refreshing ? '读取中…' : '刷新' }}
      </Button></div>
    </div>
    <p v-if="!state.settings.antigravityEnabled" class="notice">Antigravity 监测已关闭，可在设置中开启。</p>
    <p v-if="state.antigravity.error" class="notice warning" role="status">{{ state.antigravity.error }}<span v-if="state.antigravity.lastSuccess"> 上次读数已过期。</span></p>
    <div v-for="(group, index) in state.antigravity.groups" :key="index" class="antigravity-group">
      <h3>{{ group.name }}</h3>
      <div class="antigravity-buckets">
        <div v-for="bucket in group.buckets" :key="bucket.id" class="quota-window" :class="tone(bucket.remainingPercent)" :title="`额度桶：${bucket.id}`">
          <div class="quota-label-row"><div><h4>{{ windowLabel(bucket.window) }}</h4><small>{{ bucket.name }}</small></div><strong>{{ bucket.disabled ? '未启用' : bucket.remainingPercent === null ? '未知' : `${Math.floor(bucket.remainingPercent)}%` }}</strong></div>
          <div v-if="bucket.remainingPercent !== null" class="quota-track" aria-hidden="true"><div :style="{ width: `${bucket.remainingPercent}%` }" /></div>
          <div class="quota-time-row"><span v-if="countdown(bucket.resetsAt, now)" class="deadline-countdown">{{ countdown(bucket.resetsAt, now) }}</span><span v-if="bucket.resetsAt !== null" class="muted">重置 · {{ dateText(bucket.resetsAt) }}</span></div>
        </div>
      </div>
    </div>
    <div class="antigravity-footer muted"><span>CLI 未提供可验证的账号身份，暂不记录历史或提醒恢复。</span><span v-if="state.antigravity.lastSuccess !== null">上次读取 · {{ dateText(state.antigravity.lastSuccess) }}</span></div>
  </section>
</template>

<style scoped>
.antigravity-group { margin-top: 20px; }
.antigravity-buckets { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px 24px; margin-top: 6px; }
.quota-window + .quota-window { margin-top: 0; }
.quota-label-row { gap: 16px; }
.quota-label-row > div { min-width: 0; overflow-wrap: anywhere; }
.quota-label-row strong { flex-shrink: 0; }
.unknown { --quota-color: var(--muted); }
.quota-time-row { flex-wrap: wrap; gap: 4px 12px; }
.antigravity-footer { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 8px 20px; font-size: 12px; margin-top: 20px; }
@media (max-width: 820px) { .antigravity-buckets { grid-template-columns: 1fr; } }
</style>
