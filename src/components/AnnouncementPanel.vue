<script setup lang="ts">
import { computed } from 'vue'
import { ArrowUpRight } from '@lucide/vue'
import type { Announcement, AnnouncementSnapshot } from '@/types'
import { dateText } from '@/lib/usage'
import { openExternal } from '@/lib/app'
import antigravityIcon from '@/assets/antigravity.svg'

const props = defineProps<{
  feed?: AnnouncementSnapshot
  service?: 'Codex' | 'Antigravity' | 'all'
  now: number
  codexFeed?: AnnouncementSnapshot
  antigravityFeed?: AnnouncementSnapshot
}>()

const activeService = computed(() => props.service ?? 'Codex')
const source = computed(() => activeService.value === 'Antigravity' ? 'antigravity-reset' : 'codex-reset')

interface MergedItem {
  service: 'Codex' | 'Antigravity'
  event: Announcement
  post?: Announcement['posts'][number]
}

const announcements = computed<MergedItem[]>(() => {
  if (activeService.value === 'all') {
    const list: MergedItem[] = []
    for (const event of props.codexFeed?.events ?? []) {
      const post = event.posts.slice().sort((a, b) => b.publishedAt - a.publishedAt)[0]
      list.push({ service: 'Codex', event, post })
    }
    for (const event of props.antigravityFeed?.events ?? []) {
      const post = event.posts.slice().sort((a, b) => b.publishedAt - a.publishedAt)[0]
      list.push({ service: 'Antigravity', event, post })
    }
    return list.sort((a, b) => b.event.updatedAt - a.event.updatedAt).slice(0, 4)
  }
  return (props.feed?.events ?? []).slice().sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 3).map(event => ({
    service: activeService.value as 'Codex' | 'Antigravity',
    event,
    post: event.posts.slice().sort((a, b) => b.publishedAt - a.publishedAt)[0],
  }))
})

const isRefreshing = computed(() => {
  if (activeService.value === 'all') return Boolean(props.codexFeed?.refreshing || props.antigravityFeed?.refreshing)
  return Boolean(props.feed?.refreshing)
})

const errorMessage = computed(() => {
  if (activeService.value === 'all') return props.codexFeed?.error ?? props.antigravityFeed?.error ?? props.codexFeed?.sourceStatus ?? props.antigravityFeed?.sourceStatus
  return props.feed?.error ?? props.feed?.sourceStatus
})

function status(item: MergedItem) {
  const event = item.event
  if (event.status === 'confirmed') return event.confirmationBasis === 'source_post' ? `${item.service === 'Codex' ? 'Tibo' : 'Varun'} 已确认` : event.confirmationBasis === 'receipt_review' ? 'AIHOT 到账核实' : '公告已确认'
  if (event.presentation?.status === 'likely_completed' || event.presentation?.status === 'expired_unconfirmed' || (event.estimate?.through ?? event.schedule?.through ?? Infinity) < props.now) return '已过预计时间，未确认'
  return event.presentation?.status === 'in_progress' ? '正在生效' : '已预告'
}
</script>

<template>
  <section class="surface announcement-surface">
    <div class="section-heading">
      <div class="service-title-group">
        <template v-if="activeService === 'all'">
          <h2>公开重置动态</h2>
          <span class="brand-meta-tag">AIHOT</span>
        </template>
        <template v-else>
          <span v-if="activeService === 'Codex'" class="service-icon codex-icon" aria-hidden="true" />
          <img v-else class="service-icon" :src="antigravityIcon" alt="" aria-hidden="true" />
          <h2>{{ activeService }} 重置动态</h2>
        </template>
      </div>
      <button class="text-link" @click="openExternal(`https://aihot.news/${source}`)">AIHOT <ArrowUpRight :size="13" /></button>
    </div>
    <p class="muted">公开公告，不代表个人额度已恢复。</p>
    <p v-if="errorMessage" class="notice warning" role="status">{{ errorMessage }}</p>
    <div v-if="!announcements.length" class="empty-state announcement-empty">{{ isRefreshing ? '正在读取公开动态…' : '暂无公开动态' }}</div>
    <article v-for="{ service: itemService, event, post } in announcements" :key="event.id" class="announcement">
      <div class="section-heading">
        <div class="announcement-title">
          <span v-if="activeService === 'all'" class="announcement-service-tag" :class="itemService === 'Codex' ? 'tag-codex' : 'tag-antigravity'">{{ itemService }}</span>
          <h3>{{ event.displayLabel ?? (event.type === 'reset_credit' ? '发放重置卡' : '额度重置') }}</h3>
        </div>
        <span>{{ status({ service: itemService, event, post }) }}</span>
      </div>
      <p v-if="event.presentation?.scopeLabel" class="muted">适用范围 · {{ event.presentation.scopeLabel }}</p><p v-if="post">{{ post.text }}</p>
      <div class="announcement-footer"><span v-if="post">原帖 · {{ dateText(post.publishedAt) }}</span><button v-if="post" class="text-link" @click="openExternal(post.url)">查看原帖 <ArrowUpRight :size="13" /></button></div>
      <p v-if="event.status === 'announced' && event.schedule" class="muted">预告 · {{ event.schedule.label }}</p><p v-else-if="event.status === 'announced' && event.estimate" class="muted">AIHOT 估计 · {{ event.estimate.label }}</p>
    </article>
  </section>
</template>
