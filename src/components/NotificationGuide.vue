<script setup lang="ts">
import { computed, watch } from 'vue'
import { actionError, execute, notificationGuideOpen, snapshot, systemCommand } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog'

// Finish the release notes first when both first-run dialogs are pending.
const visible = computed(() => notificationGuideOpen.value && snapshot.value.installedReleaseNotes === null)
watch(visible, open => {
  if (open && !snapshot.value.notificationGuideShown) void execute('mark_notification_guide_shown')
}, { immediate: true })
async function openSettings() {
  await systemCommand('open_notification_settings')
  if (!actionError.value) notificationGuideOpen.value = false
}
</script>

<template>
  <Dialog :open="visible" @update:open="notificationGuideOpen = $event">
    <DialogContent>
      <DialogHeader><DialogTitle>开启持久通知</DialogTitle><DialogDescription>在系统设置 → 通知中选择 Codex Quota，开启“允许通知”，并将桌面提醒样式设为“持续”或“提醒”。提醒将保留到手动关闭。</DialogDescription></DialogHeader>
      <div class="dialog-actions"><Button variant="outline" @click="notificationGuideOpen = false">暂不设置</Button><Button @click="openSettings">前往设置…</Button></div>
    </DialogContent>
  </Dialog>
</template>
