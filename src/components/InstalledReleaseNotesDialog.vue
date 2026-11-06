<script setup lang="ts">
import { ref } from 'vue'
import { execute, snapshot } from '@/lib/app'
import { Button } from '@/components/ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import ReleaseNotes from './ReleaseNotes.vue'

const saving = ref(false)
const dismissed = ref(false)
async function dismiss() {
  if (saving.value) return
  saving.value = true
  await execute('mark_release_notes_shown')
  dismissed.value = true
  saving.value = false
}
</script>

<template>
  <Dialog :open="snapshot.installedReleaseNotes !== null && !dismissed" @update:open="value => { if (!value) dismiss() }">
    <DialogContent class="installed-notes-dialog" :aria-describedby="undefined">
      <DialogHeader><DialogTitle>{{ snapshot.version }} 更新说明</DialogTitle></DialogHeader>
      <div class="installed-notes-content"><ReleaseNotes v-if="snapshot.installedReleaseNotes" :notes="snapshot.installedReleaseNotes" /></div>
      <div class="dialog-actions"><Button :disabled="saving" @click="dismiss">完成</Button></div>
    </DialogContent>
  </Dialog>
</template>

<style scoped>
.installed-notes-dialog { width: min(640px, calc(100vw - 48px)); max-width: none; }
.installed-notes-content { max-height: min(480px, calc(100vh - 220px)); overflow: auto; }
</style>
