<script setup lang="ts">
import { deepClone } from '@pmun/utils'
import { computed, nextTick, ref, useTemplateRef, watch } from 'vue'
import { Plus, RefreshCw, Search } from '@lucide/vue'
import type { AppSnapshot, ModelPricing, TokenRates, UsageService } from '@/types'
import { actionError, execute, isPreview, openExternal } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import { usageService } from '@/lib/usage-filters'

const props = defineProps<{ open: boolean; state: AppSnapshot }>()
const emit = defineEmits<{ 'update:open': [value: boolean] }>()
const search = ref('')
const service = ref<UsageService>('codex')
const scope = ref<'all' | 'used' | 'unpriced' | 'custom'>('all')
const editing = ref<ModelPricing | null>(null)
const busy = ref<'update' | 'save' | 'reset' | null>(null)
const error = ref<string | null>(null)
const updated = ref(false)
const returnTarget = ref<string | null>(null)
const tableScroll = useTemplateRef<HTMLElement>('tableScroll')
const editorForm = useTemplateRef<HTMLFormElement>('editorForm')
const emptyRates = (): TokenRates => ({ input: null, output: null, cached: null, cacheWrite: null, cacheWriteLong: null })
const fields = [
  { key: 'input', label: '新增输入' }, { key: 'output', label: '输出' }, { key: 'cached', label: '缓存命中' },
  { key: 'cacheWrite', label: '缓存写入（短期）' }, { key: 'cacheWriteLong', label: '缓存写入（长期）' },
] as const
const usage = computed(() => {
  const counts = new Map<string, { count: number; unpriced: number }>()
  for (const record of props.state.usage.records) {
    if (record.service !== service.value) continue
    const model = record.model.toLowerCase()
    const total = counts.get(model) ?? { count: 0, unpriced: 0 }
    total.count++
    if (record.cost === null) total.unpriced++
    counts.set(model, total)
  }
  return counts
})
const rows = computed(() => props.state.prices.filter(price => price.service === service.value).map(price => ({
  price, usage: usage.value.get(price.model.toLowerCase()), missing: Object.values(price.rates).every(value => value === null),
})))
const filtered = computed(() => {
  const query = search.value.trim().toLowerCase()
  return rows.value.filter(row => row.price.model.toLowerCase().includes(query) && (
    scope.value === 'all' || scope.value === 'used' && row.usage || scope.value === 'unpriced' && row.usage?.unpriced || scope.value === 'custom' && row.price.custom
  )).sort((a, b) => Number(!!b.usage?.unpriced) - Number(!!a.usage?.unpriced) || Number(!!b.usage) - Number(!!a.usage) || a.price.model.localeCompare(b.price.model))
})
watch(() => props.open, open => {
  search.value = ''; scope.value = 'all'; editing.value = null; error.value = null; updated.value = false; returnTarget.value = null
  if (open) service.value = usageService.value === 'antigravity' ? 'antigravity' : 'codex'
})
watch([service, scope, search], () => tableScroll.value?.scrollTo({ top: 0 }))

async function edit(price?: ModelPricing) {
  returnTarget.value = price?.model ?? null
  error.value = null
  updated.value = false
  editing.value = price ? deepClone(price) : { service: service.value, model: '', rates: emptyRates(), contextThreshold: null, longContextRates: null, fastMultiplier: null, ultrafastMultiplier: null }
  await nextTick()
  editorForm.value?.querySelector<HTMLInputElement>('input:not([readonly])')?.focus()
}
async function closeEditor(targetModel = returnTarget.value) {
  editing.value = null
  error.value = null
  await nextTick()
  if (!props.open) return
  const button = targetModel ? tableScroll.value?.querySelector<HTMLButtonElement>(`[data-edit-model="${CSS.escape(targetModel)}"]`) : null
  ;(button ?? document.getElementById('pricing-add-button'))?.focus()
}
function setRate(rates: TokenRates, key: keyof TokenRates, event: Event) {
  const value = (event.target as HTMLInputElement).value
  rates[key] = value === '' ? null : value
}
async function updatePrices() {
  busy.value = 'update'; error.value = null; updated.value = false
  await execute('update_prices')
  error.value = actionError.value
  updated.value = !error.value
  busy.value = null
}
async function resetPrice() {
  if (!returnTarget.value) return
  busy.value = 'reset'; error.value = null
  await execute('reset_price', { service: service.value, model: returnTarget.value })
  error.value = actionError.value
  busy.value = null
  if (!error.value) await closeEditor()
}
async function save() {
  if (!editing.value) return
  error.value = null
  const price = editing.value
  const model = price.model.trim()
  if (!model) { error.value = '请输入模型名称。'; return }
  if (!returnTarget.value && rows.value.some(row => row.price.model.toLowerCase() === model.toLowerCase())) { error.value = '此模型已在列表中，请返回后编辑。'; return }
  const longContextRates = price.contextThreshold === null ? null : price.longContextRates
  const rates = [...Object.values(price.rates), ...Object.values(longContextRates ?? {})]
  if (rates.some(value => value !== null && (!Number.isFinite(Number(value)) || Number(value) < 0 || Number(value) >= 1e9))) { error.value = '单价应大于等于 0 且小于 1,000,000,000。'; return }
  if ([price.fastMultiplier, price.ultrafastMultiplier].some(value => value !== null && (!Number.isFinite(Number(value)) || Number(value) <= 0 || Number(value) >= 1000))) { error.value = '倍率应大于 0 且小于 1,000。'; return }
  if (price.contextThreshold != null && (!Number.isInteger(price.contextThreshold) || price.contextThreshold <= 0 || price.contextThreshold >= 1e8)) { error.value = '长上下文阈值应为有效的正整数。'; return }
  busy.value = 'save'
  await execute('save_prices', { prices: [{ ...price, model, longContextRates, custom: true }] })
  error.value = actionError.value
  busy.value = null
  if (!error.value) await closeEditor(model)
}
</script>

<template>
  <Dialog :open="open" @update:open="!busy && emit('update:open', $event)">
    <DialogContent class="pricing-dialog" :show-close-button="!busy" @escape-key-down="editing && ($event.preventDefault(), !busy && closeEditor())">
      <DialogHeader>
        <DialogTitle>{{ editing ? `${service === 'codex' ? 'Codex' : 'Antigravity'} 模型定价` : '模型定价' }}</DialogTitle>
        <DialogDescription>美元 / 百万 Tokens · API 等价估算。空白为未知，0 为免费。</DialogDescription>
      </DialogHeader>
      <template v-if="!editing">
        <div class="pricing-toolbar">
          <NativeSelect v-model="service" aria-label="定价服务" :disabled="!!busy"><NativeSelectOption value="codex">Codex</NativeSelectOption><NativeSelectOption value="antigravity">Antigravity</NativeSelectOption></NativeSelect>
          <NativeSelect v-model="scope" aria-label="模型范围" :disabled="!!busy"><NativeSelectOption value="all">全部模型</NativeSelectOption><NativeSelectOption value="used">有用量</NativeSelectOption><NativeSelectOption value="unpriced">含未定价</NativeSelectOption><NativeSelectOption value="custom">自定义</NativeSelectOption></NativeSelect>
          <label class="search-box"><Search :size="14" /><input v-model="search" :disabled="!!busy" placeholder="搜索模型" aria-label="搜索模型" /></label>
          <Button variant="outline" size="sm" :disabled="!!busy" @click="updatePrices"><RefreshCw :size="14" :class="{ spinning: busy === 'update' }" />{{ busy === 'update' ? '更新中…' : '更新官方价格' }}</Button>
          <Button id="pricing-add-button" variant="outline" size="sm" :disabled="!!busy" @click="edit()"><Plus :size="14" />添加…</Button>
        </div>
        <div class="pricing-meta muted"><span>价格快照 · {{ state.priceDate || '内置' }}</span><span class="pricing-sources"><button @click="openExternal('https://developers.openai.com/api/docs/pricing')">OpenAI</button><template v-if="service === 'antigravity'"><button @click="openExternal('https://ai.google.dev/gemini-api/docs/pricing')">Google</button><button @click="openExternal('https://platform.claude.com/docs/en/about-claude/pricing')">Anthropic</button></template></span><span>{{ filtered.length }} 个模型</span></div>
        <p v-if="error" class="notice warning" role="alert">{{ error }}</p>
        <p v-else-if="updated" class="muted" role="status">{{ isPreview ? '离线预览不下载官方价格。' : '官方价格已更新，自定义价格已保留。' }}</p>
        <div ref="tableScroll" class="table-scroll">
          <table class="pricing-table">
            <thead><tr><th>模型</th><th class="number">输入</th><th class="number">输出</th><th class="number">缓存命中</th><th class="number">未定价记录</th><th class="number"><span class="sr-only">操作</span></th></tr></thead>
            <tbody><tr v-for="row in filtered" :key="`${row.price.service}:${row.price.model}`">
              <td><span class="model-cell">{{ row.price.model }}</span><small v-if="row.price.custom" class="muted"> 自定义</small><small v-else-if="row.missing" class="unpriced-text"> 未定价</small><small v-if="row.price.contextThreshold" class="pricing-rule muted">长上下文 &gt; {{ row.price.contextThreshold.toLocaleString('zh-CN') }}</small></td>
              <td class="number">{{ row.price.rates.input ?? '—' }}</td><td class="number">{{ row.price.rates.output ?? '—' }}</td><td class="number">{{ row.price.rates.cached ?? '—' }}</td>
              <td class="number" :class="{ 'unpriced-text': row.usage?.unpriced }">{{ row.usage ? row.usage.unpriced.toLocaleString('zh-CN') : '—' }}</td>
              <td class="number"><span v-if="row.price.model === 'unknown'" class="muted" title="日志未报告模型，无法指定价格">模型未知</span><Button v-else variant="ghost" size="sm" :disabled="!!busy" :data-edit-model="row.price.model" :aria-label="`编辑 ${row.price.model} 定价`" @click="edit(row.price)">编辑…</Button></td>
            </tr></tbody>
          </table>
          <p v-if="!filtered.length" class="empty-state">{{ scope === 'unpriced' && !search ? '没有未定价记录' : '没有匹配的模型' }}</p>
        </div>
        <div class="dialog-actions"><Button :disabled="!!busy" @click="emit('update:open', false)">完成</Button></div>
      </template>
      <form v-else ref="editorForm" class="price-editor" @input="error = null" @submit.prevent="save">
        <div class="price-editor-fields">
          <label class="field">模型名称<Input v-model="editing.model" :disabled="!!busy" :readonly="returnTarget !== null" required placeholder="如 gpt-6.1-sol" /></label>
          <fieldset class="price-section" :disabled="!!busy">
            <legend>标准单价</legend>
            <div class="price-grid"><label v-for="field in fields" :key="field.key" class="field">{{ field.label }}<input type="number" min="0" max="999999999" step="any" placeholder="未知" :value="editing.rates[field.key] ?? ''" @input="setRate(editing.rates, field.key, $event)" /></label></div>
          </fieldset>
          <fieldset v-if="service === 'codex'" class="price-section" :disabled="!!busy">
            <legend>速度倍率</legend>
            <div class="price-grid">
              <label class="field">Fast<input type="number" min="0.001" max="999.999" step="any" placeholder="未知" :value="editing.fastMultiplier ?? ''" @input="editing.fastMultiplier = ($event.target as HTMLInputElement).value || null" /></label>
              <label class="field">Ultrafast<input type="number" min="0.001" max="999.999" step="any" placeholder="未知" :value="editing.ultrafastMultiplier ?? ''" @input="editing.ultrafastMultiplier = ($event.target as HTMLInputElement).value || null" /></label>
            </div>
          </fieldset>
          <fieldset class="price-section" :disabled="!!busy">
            <legend>长上下文</legend>
            <div class="price-grid"><label class="field">输入阈值（Tokens）<input type="number" min="1" max="99999999" step="1" placeholder="不分档" :value="editing.contextThreshold ?? ''" @input="editing.contextThreshold = ($event.target as HTMLInputElement).value ? Number(($event.target as HTMLInputElement).value) : null; editing.longContextRates ??= emptyRates()" /></label></div>
            <template v-if="editing.contextThreshold">
              <p class="muted price-context-note">单条请求的全部输入（含缓存）超过阈值时，使用以下单价。</p>
              <div class="price-grid"><label v-for="field in fields" :key="field.key" class="field">{{ field.label }}<input type="number" min="0" max="999999999" step="any" placeholder="未知" :value="editing.longContextRates?.[field.key] ?? ''" @input="setRate(editing.longContextRates ??= emptyRates(), field.key, $event)" /></label></div>
            </template>
          </fieldset>
        </div>
        <p v-if="error" class="notice warning" role="alert">{{ error }}</p>
        <div class="dialog-actions">
          <Button v-if="editing.custom && returnTarget" type="button" variant="outline" :disabled="!!busy" @click="resetPrice">{{ busy === 'reset' ? '移除中…' : '移除自定义' }}</Button>
          <div class="filter-spacer" /><Button type="button" variant="outline" :disabled="!!busy" @click="closeEditor()">取消</Button><Button :disabled="!!busy" type="submit">{{ busy === 'save' ? '保存中…' : '保存' }}</Button>
        </div>
      </form>
    </DialogContent>
  </Dialog>
</template>
