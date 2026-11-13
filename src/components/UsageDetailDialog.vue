<script setup lang="ts">
import { computed } from 'vue'
import type { AppSnapshot, UsageRecord } from '@/types'
import { billingTier, costLabel, costTooltip, shortTokens, summarize, summaryMoney } from '@/lib/usage'
import UsageRecordTable from './UsageRecordTable.vue'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'

const props = defineProps<{ title: string; records: UsageRecord[]; state: AppSnapshot }>()
const emit = defineEmits<{ close: [] }>()
const total = computed(() => summarize(props.records))
const sessions = computed(() => [...new Set(props.records.map(record => record.session))])
const directories = computed(() => [...new Set(props.records.map(record => record.project))].filter(Boolean).sort().map(directory => ({ directory, root: props.state.usage.projectRoots[directory] ?? directory })))
const tiers = computed(() => {
  const groups = new Map<string, UsageRecord[]>()
  for (const record of props.records) {
    const tier = billingTier(record), items = groups.get(tier) ?? []
    items.push(record); groups.set(tier, items)
  }
  return ['Standard', 'Fast', 'Ultrafast', '未知档位'].filter(tier => groups.has(tier)).map(tier => ({ tier, total: summarize(groups.get(tier)!) }))
})
</script>
<template>
  <Dialog :open="true" @update:open="value => { if (!value) emit('close') }"><DialogContent class="detail-dialog"><DialogHeader><DialogTitle>{{ title }}</DialogTitle><DialogDescription>{{ records.length }} 条用量记录 · 当前筛选范围</DialogDescription></DialogHeader>
    <div class="detail-context">
      <div class="detail-totals"><strong>{{ total.tokens.toLocaleString('zh-CN') }} Tokens</strong><span>{{ costLabel(total) }} <strong :class="{ 'unpriced-text': total.count && !total.priced }" :title="costTooltip(total)">{{ summaryMoney(total) }}</strong><span class="muted"> · API 等价估算</span><span v-if="total.unpriced" class="unpriced-text"> · {{ total.unpriced.toLocaleString('zh-CN') }} 条未定价</span></span></div>
      <div v-if="sessions.length === 1" class="session-identity"><span class="muted">会话 ID</span><code>{{ sessions[0] }}</code></div>
      <details v-else><summary>会话 ID（{{ sessions.length }}）</summary><code v-for="session in sessions" :key="session" class="session-id">{{ session }}</code></details>
      <details v-if="directories.length"><summary>工作目录</summary><div v-for="{ directory, root } in directories" :key="directory" class="directory"><code>{{ directory }}</code><div v-if="root !== directory" class="muted">主项目：<code>{{ root }}</code></div></div></details>
      <div v-if="tiers.length > 1" class="tier-summary"><div v-for="item in tiers" :key="item.tier"><h3>{{ item.tier }}</h3><span :title="item.total.tokens.toLocaleString()">{{ shortTokens(item.total.tokens) }} Tokens</span><span class="muted" :title="costTooltip(item.total)">{{ costLabel(item.total) }} {{ summaryMoney(item.total) }}<template v-if="item.total.unpriced"> · <span class="unpriced-text">{{ item.total.unpriced.toLocaleString('zh-CN') }} 条未定价</span></template></span></div></div>
    </div>
    <UsageRecordTable :records="records" :state="state" />
    <div class="dialog-actions"><Button @click="emit('close')">完成</Button></div>
  </DialogContent></Dialog>
</template>
<style scoped>
.detail-context { display: grid; gap: 12px; font-size: 12px; max-height: 32vh; overflow: auto; flex-shrink: 0; }
.detail-totals, .session-identity { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px 16px; font-variant-numeric: tabular-nums; }
.detail-context code { user-select: text; overflow-wrap: anywhere; }
.detail-context summary { cursor: pointer; width: fit-content; }
.session-id { display: block; margin-top: 6px; }
.directory { display: grid; gap: 4px; margin-top: 8px; }
.tier-summary { display: flex; flex-wrap: wrap; gap: 12px 28px; padding-top: 12px; border-top: 1px solid var(--border); font-variant-numeric: tabular-nums; }
.tier-summary > div { display: grid; gap: 4px; }
</style>
