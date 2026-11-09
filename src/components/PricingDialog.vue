<script setup lang="ts">
import { deepClone } from '@pmun/utils'
import { computed, nextTick, ref, useTemplateRef, watch } from 'vue'
import { Plus, Search } from '@lucide/vue'
import type { AppSnapshot, ModelPricing, TokenRates, UsageService } from '@/types'
import { actionError, execute } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import { usageService } from '@/lib/usage-filters'
const props = defineProps<{ open: boolean; state: AppSnapshot }>()
const emit = defineEmits<{ 'update:open': [value: boolean] }>()
const search = ref('')
const service = ref<UsageService>(usageService.value === 'antigravity' ? 'antigravity' : 'codex')
const editing = ref<ModelPricing | null>(null)
const busy = ref(false)
const error = ref<string | null>(null)
const returnTarget = ref<string | null>(null)
const tableScroll = useTemplateRef<HTMLElement>('tableScroll')
const editorForm = useTemplateRef<HTMLFormElement>('editorForm')
const emptyRates = (): TokenRates => ({ input: null, output: null, cached: null, cacheWrite: null, cacheWriteLong: null })
const fields = [{ key: 'input', label: '新增输入' }, { key: 'output', label: '输出' }, { key: 'cached', label: '缓存命中' }, { key: 'cacheWrite', label: '缓存写入（短期）' }, { key: 'cacheWriteLong', label: '缓存写入（长期）' }] as const
const filtered = computed(() => props.state.prices.filter(price => price.service === service.value && price.model.toLowerCase().includes(search.value.toLowerCase())))
watch(() => props.open, open => {
  if (!open) { search.value = ''; editing.value = null; error.value = null; busy.value = false; returnTarget.value = null }
})
async function edit(price?: ModelPricing) {
  returnTarget.value = price?.model ?? null
  error.value = null
  editing.value = price ? deepClone(price) : { service: service.value, model: '', rates: emptyRates(), contextThreshold: null, longContextRates: null, fastMultiplier: null, ultrafastMultiplier: null, custom: true }
  await nextTick()
  editorForm.value?.querySelector<HTMLInputElement>('input')?.focus()
}
async function closeEditor(targetModel = returnTarget.value) {
  editing.value = null
  error.value = null
  await nextTick()
  if (!props.open) return
  const button = targetModel ? tableScroll.value?.querySelector<HTMLButtonElement>(`[data-edit-model="${CSS.escape(targetModel)}"]`) : null
  ;(button ?? document.getElementById('pricing-add-button'))?.focus()
}
function setRate(rates: TokenRates, key: keyof TokenRates, event: Event) { const value = (event.target as HTMLInputElement).value; rates[key] = value === '' ? null : value }
async function updatePrices() {
  busy.value = true
  await execute('update_prices')
  busy.value = false
}
async function resetPrice(model: string) {
  busy.value = true
  await execute('reset_price', { service: service.value, model })
  busy.value = false
  if (!actionError.value) await closeEditor(model)
}
async function save() {
  if (!editing.value) return
  const price = editing.value
  const model = price.model.trim()
  if (!model) { error.value = '请输入模型名称。'; return }
  const rates = [...Object.values(price.rates), ...Object.values(price.longContextRates ?? {})]
  if (rates.some(value => value !== null && (!Number.isFinite(Number(value)) || Number(value) < 0 || Number(value) >= 1e9))) { error.value = '单价应在 0 至 1,000,000,000 之间。'; return }
  if ([price.fastMultiplier, price.ultrafastMultiplier].some(value => value !== null && (!Number.isFinite(Number(value)) || Number(value) <= 0 || Number(value) >= 1000))) { error.value = '倍率应大于 0 且小于 1,000。'; return }
  if (price.contextThreshold != null && (!Number.isInteger(price.contextThreshold) || price.contextThreshold <= 0 || price.contextThreshold >= 1e8)) { error.value = '长上下文阈值应为有效的正整数。'; return }
  busy.value = true
  await execute('save_prices', { prices: [{ ...price, model, custom: true }] })
  busy.value = false
  if (!actionError.value) await closeEditor(model)
}
</script>
<template>
  <Dialog :open="open" @update:open="emit('update:open', $event)"><DialogContent class="pricing-dialog"><DialogHeader><DialogTitle>{{ editing ? (service === 'codex' ? 'Codex' : 'Antigravity') + ' 模型定价' : '模型定价' }}</DialogTitle><DialogDescription>每百万 Tokens 的 API 等价价格（$）。空白为未知，0 为免费。</DialogDescription></DialogHeader>
    <template v-if="!editing"><div class="pricing-toolbar"><NativeSelect v-model="service" aria-label="定价服务" :disabled="busy"><NativeSelectOption value="codex">Codex</NativeSelectOption><NativeSelectOption value="antigravity">Antigravity</NativeSelectOption></NativeSelect><label class="search-box"><Search :size="14" /><input v-model="search" :disabled="busy" placeholder="搜索模型" aria-label="搜索模型" /></label><Button variant="outline" size="sm" :disabled="busy" @click="updatePrices">更新公开价格</Button><Button id="pricing-add-button" variant="outline" size="sm" :disabled="busy" @click="edit()"><Plus :size="14" />添加…</Button></div><p class="muted">价格快照 · {{ state.priceDate || '内置' }}</p><div ref="tableScroll" class="table-scroll"><table class="pricing-table"><thead><tr><th>模型</th><th class="number">输入</th><th class="number">输出</th><th class="number">缓存命中</th><th class="number"><span class="sr-only">操作</span></th></tr></thead><tbody><tr v-for="price in filtered" :key="`${price.service}:${price.model}`"><td><span class="model-cell">{{ price.model }}</span><small v-if="price.custom" class="muted"> 自定义</small><small v-else-if="Object.values(price.rates).every(value => value === null)" class="unpriced-text"> 未定价</small></td><td class="number">{{ price.rates.input ?? '—' }}</td><td class="number">{{ price.rates.output ?? '—' }}</td><td class="number">{{ price.rates.cached ?? '—' }}</td><td class="number"><Button variant="ghost" size="sm" :disabled="busy" :data-edit-model="price.model" :aria-label="`编辑 ${price.model} 定价`" @click="edit(price)">编辑…</Button></td></tr></tbody></table><p v-if="!filtered.length" class="empty-state">没有匹配的模型</p></div><div class="dialog-actions"><Button :disabled="busy" @click="emit('update:open', false)">完成</Button></div></template>
    <form v-else ref="editorForm" class="price-editor" @submit.prevent="save"><label class="field">模型名称<Input v-model="editing.model" :disabled="busy" autofocus required placeholder="如 gpt-6.1-sol" /></label><div class="price-grid"><label v-for="field in fields" :key="field.key" class="field">{{ field.label }}<input type="number" min="0" max="999999999" step="any" :disabled="busy" :value="editing.rates[field.key] ?? ''" @input="setRate(editing.rates, field.key, $event)" /></label></div><div class="price-grid"><label v-if="service === 'codex'" class="field">Fast 倍率<input type="number" min="0.001" max="999.999" step="any" :disabled="busy" :value="editing.fastMultiplier ?? ''" @input="editing.fastMultiplier = ($event.target as HTMLInputElement).value || null" /></label><label v-if="service === 'codex'" class="field">Ultrafast 倍率<input type="number" min="0.001" max="999.999" step="any" :disabled="busy" :value="editing.ultrafastMultiplier ?? ''" @input="editing.ultrafastMultiplier = ($event.target as HTMLInputElement).value || null" /></label><label class="field">长上下文阈值<input type="number" min="1" max="99999999" step="1" :disabled="busy" :value="editing.contextThreshold ?? ''" @input="editing.contextThreshold = ($event.target as HTMLInputElement).value ? Number(($event.target as HTMLInputElement).value) : null; editing.longContextRates ??= emptyRates()" /></label></div><div v-if="editing.contextThreshold" class="price-grid"><label v-for="field in fields" :key="field.key" class="field">长上下文 · {{ field.label }}<input type="number" min="0" max="999999999" step="any" :disabled="busy" :value="editing.longContextRates?.[field.key] ?? ''" @input="setRate(editing.longContextRates ??= emptyRates(), field.key, $event)" /></label></div><p v-if="error || actionError" class="notice warning" role="alert">{{ error || actionError }}</p><div class="dialog-actions"><Button v-if="editing.custom" type="button" variant="outline" :disabled="busy" @click="resetPrice(editing.model)">恢复默认</Button><div class="filter-spacer" /><Button type="button" variant="outline" :disabled="busy" @click="closeEditor()">取消</Button><Button :disabled="busy" type="submit">{{ busy ? '保存中…' : '保存' }}</Button></div></form>
  </DialogContent></Dialog>
</template>
