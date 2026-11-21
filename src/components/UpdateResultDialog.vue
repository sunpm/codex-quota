<script setup lang="ts">
import { shallowRef, watch } from 'vue'
import { useWindowFocus } from '@vueuse/core'
import type { UpdateState } from '@/types'
import { execute, manualUpdateCheck, notificationGuideOpen, openExternal, snapshot } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'
import ReleaseNotes from './ReleaseNotes.vue'

const result = shallowRef<UpdateState | null>(null)
const windowFocused = useWindowFocus()
let dismissedVersion: string | null = null
watch(() => snapshot.value.update, update => {
  if (!['available', 'current', 'error'].includes(update.status)) return
  const manual = manualUpdateCheck.value
  manualUpdateCheck.value = false
  if (update.status === 'available' && (manual || update.version !== dismissedVersion)) {
    result.value = { ...update }
  }
}, { immediate: true })
function dismiss() {
  if (result.value) dismissedVersion = result.value.version
  result.value = null
}
</script>
<template>
  <Dialog :open="result !== null && windowFocused && snapshot.installedReleaseNotes === null && !notificationGuideOpen" @update:open="value => { if (!value) dismiss() }">
    <DialogContent class="update-result-dialog" @pointer-down-outside.prevent>
      <DialogHeader>
        <DialogTitle>发现新版本 {{ result?.version }}</DialogTitle>
        <DialogDescription>当前版本 {{ snapshot.version }}</DialogDescription>
      </DialogHeader>
      <div v-if="result?.notes" class="update-notes-content"><ReleaseNotes :notes="result.notes" /></div>
      <div class="dialog-actions">
        <Button variant="outline" @click="dismiss">{{ result?.canInstall ? '稍后' : '好' }}</Button>
        <Button v-if="result?.canInstall" @click="dismiss(); execute('install_update')">更新并重启</Button>
        <Button v-else-if="result?.version" variant="outline" @click="openExternal('https://github.com/sunpm/codex-quota/releases')">查看发布页</Button>
      </div>
    </DialogContent>
  </Dialog>
</template>

<style scoped>
.update-result-dialog { width: min(640px, calc(100vw - 48px)); max-width: none; }
.update-notes-content { max-height: min(480px, calc(100vh - 220px)); overflow: auto; }
</style>
