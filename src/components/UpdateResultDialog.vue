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
  if (update.status === 'available') result.value = { ...update }
})
</script>
<template>
  <Dialog :open="result !== null" @update:open="value => { if (!value) result = null }">
    <DialogContent>
      <DialogHeader>
        <DialogTitle>发现新版本 {{ result?.version }}</DialogTitle>
        <DialogDescription>当前版本 {{ snapshot.version }}</DialogDescription>
      </DialogHeader>
      <div class="dialog-actions">
        <Button variant="outline" @click="result = null">{{ result?.canInstall ? '稍后' : '好' }}</Button>
        <Button v-if="result?.canInstall" @click="result = null; execute('install_update')">更新并重启</Button>
        <Button v-else-if="result?.version" variant="outline" @click="openExternal('https://github.com/sunpm/codex-quota/releases')">查看发布页</Button>
      </div>
    </DialogContent>
  </Dialog>
</template>
