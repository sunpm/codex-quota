<script setup lang="ts">
import { nextTick, ref, watch } from 'vue'
import { Plus, X } from '@lucide/vue'
import { actionError, changeSettings } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { NativeSelect, NativeSelectOption } from '@/components/ui/native-select'
import { Popover, PopoverAnchor, PopoverContent } from '@/components/ui/popover'

const props = defineProps<{
  id: string
  minutes: number[]
  setting: 'resetCreditReminderMinutes' | 'quotaResetReminderMinutes'
  disabled: boolean
}>()
const open = ref(false)
const editing = ref<number | null>(null)
const amount = ref(1)
const unit = ref(60)
const error = ref('')
const saving = ref(false)
const focusTarget = ref<HTMLButtonElement | null>(null)
const interactedOutside = ref(false)
const units = [{ value: 1440, label: '天' }, { value: 60, label: '小时' }, { value: 1, label: '分钟' }]

function timeText(minutes: number) {
  const selected = units.find(unit => minutes % unit.value === 0)!
  return `${minutes / selected.value} ${selected.label}`
}
function edit(minutes: number | null, event: MouseEvent) {
  focusTarget.value = event.currentTarget as HTMLButtonElement
  interactedOutside.value = false
  editing.value = minutes
  const value = minutes ?? [1440, 300, 120, 60, 30, 10, 5, 1].find(value => !props.minutes.includes(value)) ?? 1
  unit.value = units.find(unit => value % unit.value === 0)!.value
  amount.value = value / unit.value
  error.value = ''
  open.value = true
}
async function restoreFocus(event: Event) {
  event.preventDefault()
  await nextTick()
  if (props.disabled || interactedOutside.value) return
  const target = focusTarget.value?.isConnected ? focusTarget.value : document.getElementById(`${props.id}-add`)
  target?.focus()
}
async function save() {
  const minutes = amount.value * unit.value
  if (!Number.isInteger(amount.value) || amount.value <= 0 || minutes > 4294967295) {
    error.value = '请输入有效的正整数时间。'
    return
  }
  const values = props.minutes.filter(value => value !== editing.value)
  if (values.includes(minutes)) {
    error.value = '已有相同的提醒时间。'
    return
  }
  saving.value = true
  await changeSettings({ [props.setting]: [...values, minutes].sort((a, b) => b - a) })
  saving.value = false
  if (!actionError.value) open.value = false
}
async function remove(minutes: number) {
  saving.value = true
  await changeSettings({ [props.setting]: props.minutes.filter(value => value !== minutes) })
  saving.value = false
}
watch(() => props.disabled, disabled => { if (disabled) open.value = false })
</script>

<template>
  <Popover v-model:open="open">
    <PopoverAnchor as-child>
      <div class="reminder-schedule">
        <ul class="reminder-times" aria-label="提醒时间">
          <li v-for="minutes in minutes" :key="minutes" class="reminder-time">
            <Button type="button" variant="ghost" size="sm" :disabled="disabled || saving" :aria-label="`修改提前 ${timeText(minutes)} 的提醒`" @click="edit(minutes, $event)">提前 {{ timeText(minutes) }}</Button>
            <Button type="button" variant="ghost" size="icon-xs" :disabled="disabled || saving || props.minutes.length === 1" :aria-label="`删除提前 ${timeText(minutes)} 的提醒`" @click="remove(minutes)"><X :size="12" /></Button>
          </li>
        </ul>
        <Button :id="`${id}-add`" type="button" variant="ghost" size="sm" :disabled="disabled || saving" @click="edit(null, $event)"><Plus :size="14" />添加提醒</Button>
      </div>
    </PopoverAnchor>
    <PopoverContent align="start" class="reminder-popover" @close-auto-focus="restoreFocus" @interact-outside="interactedOutside = true">
      <form @submit.prevent="save">
        <label :for="`${id}-amount`">提前时间</label>
        <div class="reminder-inputs">
          <input :id="`${id}-amount`" v-model.number="amount" type="number" min="1" :max="Math.floor(4294967295 / unit)" step="1" required :disabled="saving" :aria-invalid="!!error" :aria-describedby="error ? `${id}-error` : undefined" @input="error = ''" />
          <NativeSelect :model-value="unit" aria-label="时间单位" :disabled="saving" data-size="default" @change="unit = Number(($event.target as HTMLSelectElement).value); error = ''"><NativeSelectOption v-for="unit in units" :key="unit.value" :value="unit.value">{{ unit.label }}</NativeSelectOption></NativeSelect>
        </div>
        <p v-if="error" :id="`${id}-error`" class="reminder-error" role="alert">{{ error }}</p>
        <div class="dialog-actions"><Button type="button" variant="outline" size="sm" :disabled="saving" @click="open = false">取消</Button><Button type="submit" size="sm" :disabled="saving">保存</Button></div>
      </form>
    </PopoverContent>
  </Popover>
</template>

<style scoped>
.reminder-schedule, .reminder-times, .reminder-time { display: flex; align-items: center; }
.reminder-schedule { flex-wrap: wrap; gap: 6px; margin: 6px 0 12px; }
.reminder-times { flex-wrap: wrap; gap: 6px; margin: 0; padding: 0; list-style: none; }
.reminder-time { border: 1px solid var(--border); border-radius: 6px; padding-right: 3px; font-variant-numeric: tabular-nums; }
.reminder-popover { width: 260px; }
.reminder-inputs { display: flex; gap: 8px; margin-top: 8px; }
.reminder-inputs input { width: 100%; min-width: 0; font-variant-numeric: tabular-nums; }
.reminder-error { margin-top: 8px; color: var(--destructive); font-size: 12px; }
</style>
