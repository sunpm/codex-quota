<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { invoke } from '@tauri-apps/api/core'
import type { AppSnapshot, CostBreakdown, UsageRecord } from '@/types'
import { isPreview } from '@/lib/app'
import { previewCostBreakdown } from '@/lib/preview'
import { basename, billingTierLabel, dateText, exactMoney, reportedTokenCount, serviceName, tokenCount } from '@/lib/usage'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'

const props = defineProps<{ record: UsageRecord; state: AppSnapshot }>()
const emit = defineEmits<{ close: [] }>()
const detail = ref<CostBreakdown | null>(null)
const loading = ref(false)
const error = ref<string | null>(null)
const title = computed(() => (props.record.service === 'codex' ? props.state.usage.sessionTitles[props.record.session] : undefined) || basename(props.state.usage.projectRoots[props.record.project] ?? props.record.project))
const labels = { input: '新增输入', output: '输出', cached: '缓存命中', cacheWrite: '缓存写入', cacheWriteLong: '长时缓存写入' }
const components = computed(() => detail.value?.components.filter(component => component.kind !== 'cacheWriteLong' || component.tokens > 0) ?? [])
async function load() {
  loading.value = true
  error.value = null
  if (isPreview) detail.value = previewCostBreakdown(props.record)
  else await invoke<CostBreakdown>('usage_cost_detail', { recordId: props.record.id }).then(value => { detail.value = value }, reason => { error.value = String(reason) })
  loading.value = false
}
onMounted(load)
</script>

<template>
  <Dialog :open="true" @update:open="value => { if (!value) emit('close') }"><DialogContent class="cost-dialog"><DialogHeader><DialogTitle>用量记录</DialogTitle><DialogDescription>{{ dateText(record.date, true) }} · {{ serviceName(record.service) }} · {{ record.model }}</DialogDescription></DialogHeader>
    <div class="record-cost-body">
      <dl class="record-identity"><div><dt>对话</dt><dd>{{ title }}</dd></div><div><dt>会话 ID</dt><dd><code>{{ record.session }}</code></dd></div><div><dt>项目</dt><dd><code>{{ record.project || '未知项目' }}</code></dd></div></dl>
      <div class="record-billing"><span>{{ record.service === 'antigravity' ? '按模型单价' : billingTierLabel(record) }}</span><span>{{ tokenCount(record).toLocaleString('zh-CN') }} Tokens</span><template v-if="detail"><span>倍率 {{ detail.multiplier === null ? '未知' : `×${detail.multiplier}` }}</span><span v-if="detail.longContext">长上下文 · 输入超过 {{ detail.contextThreshold?.toLocaleString('zh-CN') }} Tokens</span></template></div>
      <div v-if="loading" class="empty-state" role="status">正在读取费用明细…</div>
      <div v-else-if="error" class="notice warning" role="alert">{{ error }}<Button variant="outline" size="sm" @click="load">重试</Button></div>
      <template v-else-if="detail">
        <div class="table-scroll"><table class="cost-breakdown"><thead><tr><th>用量</th><th class="number">Tokens</th><th class="number">单价 / 百万 Tokens</th><th class="number">费用</th></tr></thead><tbody><tr v-for="component in components" :key="component.kind"><td>{{ labels[component.kind] }}</td><td class="number">{{ reportedTokenCount(record, component.kind) === null ? '未报告' : component.tokens.toLocaleString('zh-CN') }}</td><td class="number">{{ component.rate === null ? '未知' : exactMoney(component.rate) }}</td><td class="number" :class="{ 'unpriced-text': component.amount === null }">{{ reportedTokenCount(record, component.kind) === null ? '—' : exactMoney(component.amount) }}</td></tr></tbody><tfoot><tr><th colspan="3">合计<span class="muted"> · API 等价估算</span></th><td class="number" :class="{ 'unpriced-text': detail.total === null }"><strong>{{ exactMoney(detail.total) }}</strong></td></tr></tfoot></table></div>
        <p v-if="detail.pricingModel" class="muted pricing-model">计价模型 · {{ detail.pricingModel }}</p>
        <p v-if="detail.total === null" class="unpriced-text">{{ record.service === 'antigravity' && record.tokens.cacheWrite > 0 ? '缓存写入时长未报告，无法计算完整费用。' : '缺少所需用量、单价或档位倍率，无法计算完整费用。' }}</p>
      </template>
    </div>
    <div class="dialog-actions"><Button @click="emit('close')">完成</Button></div>
  </DialogContent></Dialog>
</template>

<style scoped>
.record-cost-body { overflow: auto; min-height: 0; display: grid; gap: 16px; font-size: 12px; }
.record-identity { display: grid; gap: 10px; margin: 0; }
.record-identity > div { display: grid; grid-template-columns: 64px minmax(0, 1fr); gap: 12px; }
dt, .record-billing, .pricing-model { color: var(--muted); }
dd { margin: 0; overflow-wrap: anywhere; user-select: text; }
code { font-size: 11px; }
.record-billing { display: flex; gap: 8px 18px; flex-wrap: wrap; font-variant-numeric: tabular-nums; }
.cost-breakdown { min-width: 560px; }
.cost-breakdown tfoot th { position: static; font-weight: 500; }
.cost-breakdown tfoot td { border-bottom: 1px solid var(--border); }
.cost-breakdown tfoot span { font-weight: 400; font-size: 11px; }
</style>
