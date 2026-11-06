<script setup lang="ts">
import { computed, ref } from 'vue'
import { Plus, Search } from '@lucide/vue'
import type { AppSnapshot, ModelPricing, TokenRates } from '@/types'
import { actionError, execute } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
const props = defineProps<{ open: boolean; state: AppSnapshot }>()
const emit = defineEmits<{ 'update:open': [value: boolean] }>()
const search = ref('')
const editing = ref<ModelPricing | null>(null)
const busy = ref(false)
const error = ref<string | null>(null)
const emptyRates = (): TokenRates => ({ input: null, output: null, cached: null, cacheWrite: null, cacheWriteLong: null })
const fields = [{ key: 'input', label: '新增输入' }, { key: 'output', label: '输出' }, { key: 'cached', label: '缓存命中' }, { key: 'cacheWrite', label: '缓存写入（短期）' }, { key: 'cacheWriteLong', label: '缓存写入（长期）' }] as const
const filtered = computed(() => props.state.prices.filter(price => price.model.toLowerCase().includes(search.value.toLowerCase())))
function edit(price?: ModelPricing) { error.value = null; editing.value = price ? JSON.parse(JSON.stringify(price)) : { service: 'codex', model: '', rates: emptyRates(), contextThreshold: null, longContextRates: null, fastMultiplier: null, ultrafastMultiplier: null, custom: true } }
function setRate(rates: TokenRates, key: keyof TokenRates, event: Event) { const value = (event.target as HTMLInputElement).value; rates[key] = value === '' ? null : value }
async function save() {
  if (!editing.value) return
  const price = editing.value
  if (!price.model.trim()) { error.value = '请输入模型名称。'; return }
  const rates = [...Object.values(price.rates), ...Object.values(price.longContextRates ?? {})]
  if (rates.some(value => value !== null && (!Number.isFinite(Number(value)) || Number(value) < 0 || Number(value) >= 1e9))) { error.value = '单价应在 0 至 1,000,000,000 之间。'; return }
  if ([price.fastMultiplier, price.ultrafastMultiplier].some(value => value !== null && (!Number.isFinite(Number(value)) || Number(value) <= 0 || Number(value) >= 1000))) { error.value = '倍率应大于 0 且小于 1,000。'; return }
  if (price.contextThreshold != null && (!Number.isInteger(price.contextThreshold) || price.contextThreshold <= 0 || price.contextThreshold >= 1e8)) { error.value = '长上下文阈值应为有效的正整数。'; return }
  busy.value = true
  await execute('save_prices', { prices: [{ ...price, model: price.model.trim(), custom: true }] })
  busy.value = false
  if (!actionError.value) editing.value = null
}
</script>
<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)"><DialogContent class="pricing-dialog"><DialogHeader><DialogTitle>模型定价</DialogTitle><DialogDescription>每百万 Tokens 的 API 等价价格（$）。空白为未知，0 为免费。</DialogDescription></DialogHeader>
    <template v-if="!editing"><div class="pricing-toolbar"><label class="search-box"><Search :size="14" /><input v-model="search" placeholder="搜索模型" aria-label="搜索模型" /></label><Button variant="outline" size="sm" @click="execute('update_prices')">更新公开价格</Button><Button variant="outline" size="sm" @click="edit()"><Plus :size="14" />添加…</Button></div><p class="muted">价格快照 · {{ state.priceDate || '内置' }}</p><div class="table-scroll"><table class="pricing-table"><thead><tr><th>模型</th><th class="number">输入</th><th class="number">输出</th><th class="number">缓存命中</th><th class="number" /></tr></thead><tbody><tr v-for="price in filtered" :key="price.model"><td><span class="model-cell">{{ price.model }}</span><small v-if="price.custom" class="muted"> 自定义</small><small v-else-if="Object.values(price.rates).every(value => value === null)" class="muted"> 未定价</small></td><td class="number">{{ price.rates.input ?? '—' }}</td><td class="number">{{ price.rates.output ?? '—' }}</td><td class="number">{{ price.rates.cached ?? '—' }}</td><td class="number"><Button variant="ghost" size="sm" @click="edit(price)">编辑…</Button></td></tr></tbody></table><p v-if="!filtered.length" class="empty-state">没有匹配的模型</p></div><div class="dialog-actions"><Button @click="emit('update:open', false)">完成</Button></div></template>
    <form v-else class="price-editor" @submit.prevent="save"><label class="field">模型名称<Input v-model="editing.model" autofocus required placeholder="如 gpt-6.1-sol" /></label><div class="price-grid"><label v-for="field in fields" :key="field.key" class="field">{{ field.label }}<input type="number" min="0" max="999999999" step="any" :value="editing.rates[field.key] ?? ''" @input="setRate(editing.rates, field.key, $event)" /></label></div><div class="price-grid"><label class="field">Fast 倍率<input type="number" min="0.001" max="999.999" step="any" :value="editing.fastMultiplier ?? ''" @input="editing.fastMultiplier = ($event.target as HTMLInputElement).value || null" /></label><label class="field">Ultrafast 倍率<input type="number" min="0.001" max="999.999" step="any" :value="editing.ultrafastMultiplier ?? ''" @input="editing.ultrafastMultiplier = ($event.target as HTMLInputElement).value || null" /></label><label class="field">长上下文阈值<input type="number" min="1" max="99999999" step="1" :value="editing.contextThreshold ?? ''" @input="editing.contextThreshold = ($event.target as HTMLInputElement).value ? Number(($event.target as HTMLInputElement).value) : null; editing.longContextRates ??= emptyRates()" /></label></div><div v-if="editing.contextThreshold" class="price-grid"><label v-for="field in fields" :key="field.key" class="field">长上下文 · {{ field.label }}<input type="number" min="0" max="999999999" step="any" :value="editing.longContextRates?.[field.key] ?? ''" @input="setRate(editing.longContextRates ??= emptyRates(), field.key, $event)" /></label></div><p v-if="error || actionError" class="notice warning" role="alert">{{ error || actionError }}</p><div class="dialog-actions"><Button v-if="editing.custom" type="button" variant="outline" :disabled="busy" @click="execute('reset_price', { model: editing.model }); editing = null">恢复默认</Button><div class="filter-spacer" /><Button type="button" variant="outline" @click="editing = null">取消</Button><Button :disabled="busy" type="submit">{{ busy ? '保存中…' : '保存' }}</Button></div></form>
  </DialogContent></Dialog>
</template>
