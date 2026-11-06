<script setup lang="ts">
import { shallowRef, watch } from 'vue'
import type { UpdateState } from '@/types'
import { execute, manualUpdateCheck, openExternal, snapshot } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'

const result = shallowRef<UpdateState | null>(null)
watch(() => snapshot.value.update, update => {
  if (!manualUpdateCheck.value || !['available', 'current', 'error'].includes(update.status)) return
  manualUpdateCheck.value = false
  result.value = { ...update }
})
</script>
<template>
  <Dialog :open="result !== null" @update:open="value => { if (!value) result = null }">
    <DialogContent>
      <DialogHeader>
        <DialogTitle>{{ result?.status === 'available' ? `发现新版本 ${result.version}` : result?.status === 'current' ? '已是最新版本' : '检查更新失败' }}</DialogTitle>
        <DialogDescription>{{ result?.error ?? `当前版本 ${snapshot.version}` }}</DialogDescription>
      </DialogHeader>
      <div class="dialog-actions">
        <Button variant="outline" @click="result = null">{{ result?.canInstall ? '稍后' : '好' }}</Button>
        <Button v-if="result?.canInstall" @click="result = null; execute('install_update')">更新并重启</Button>
        <Button v-else-if="result?.version" variant="outline" @click="openExternal('https://github.com/sunpm/codex-quota/releases')">查看发布页</Button>
      </div>
    </DialogContent>
  </Dialog>
</template>
