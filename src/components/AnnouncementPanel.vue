<script setup lang="ts">
import { computed } from 'vue'
import { ArrowUpRight } from '@lucide/vue'
import type { Announcement, AnnouncementSnapshot } from '@/types'
import { dateText } from '@/lib/usage'
import { openExternal } from '@/lib/app'

const props = defineProps<{ feed: AnnouncementSnapshot; service: 'Codex' | 'Antigravity'; now: number }>()
const source = computed(() => props.service === 'Codex' ? 'codex-reset' : 'antigravity-reset')
const announcements = computed(() => props.feed.events.slice().sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 3).map(event => ({ event, post: event.posts.slice().sort((a, b) => b.publishedAt - a.publishedAt)[0] })))
function status(event: Announcement) {
  if (event.status === 'confirmed') return event.confirmationBasis === 'source_post' ? `${props.service === 'Codex' ? 'Tibo' : 'Varun'} 已确认` : event.confirmationBasis === 'receipt_review' ? 'AIHOT 到账核实' : '公告已确认'
  if (event.presentation?.status === 'likely_completed' || event.presentation?.status === 'expired_unconfirmed' || (event.estimate?.through ?? event.schedule?.through ?? Infinity) < props.now) return '已过预计时间，未确认'
  return event.presentation?.status === 'in_progress' ? '正在生效' : '已预告'
}
</script>

<template>
  <section class="surface">
    <div class="section-heading"><h2>{{ service }} 重置动态</h2><button class="text-link" @click="openExternal(`https://aihot.news/${source}`)">AIHOT <ArrowUpRight :size="13" /></button></div>
    <p class="muted">公开公告，不代表个人额度已恢复。</p>
    <p v-if="feed.error || feed.sourceStatus" class="notice warning" role="status">{{ feed.error ?? feed.sourceStatus }}<span v-if="feed.error && feed.events.length"> 上次动态已过期。</span></p>
    <div v-if="!announcements.length" class="empty-state">{{ feed.refreshing ? '正在读取公开动态…' : '暂无公开动态' }}</div>
    <article v-for="{ event, post } in announcements" :key="event.id" class="announcement">
      <div class="section-heading"><h3>{{ event.displayLabel ?? (event.type === 'reset_credit' ? '发放重置卡' : '额度重置') }}</h3><span>{{ status(event) }}</span></div>
      <p v-if="event.presentation?.scopeLabel" class="muted">适用范围 · {{ event.presentation.scopeLabel }}</p><p v-if="post">{{ post.text }}</p>
      <div class="announcement-footer"><span v-if="post">原帖 · {{ dateText(post.publishedAt) }}</span><button v-if="post" class="text-link" @click="openExternal(post.url)">查看原帖 <ArrowUpRight :size="13" /></button></div>
      <p v-if="event.status === 'announced' && event.schedule" class="muted">预告 · {{ event.schedule.label }}</p><p v-else-if="event.status === 'announced' && event.estimate" class="muted">AIHOT 估计 · {{ event.estimate.label }}</p>
    </article>
  </section>
</template>
