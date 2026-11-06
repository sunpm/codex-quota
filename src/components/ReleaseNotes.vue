<script setup lang="ts">
import { computed } from 'vue'
import MarkdownIt from 'markdown-it'
import DOMPurify from 'dompurify'
import { openExternal } from '@/lib/app'

const props = defineProps<{ notes: string }>()
const markdown = new MarkdownIt({ html: true, linkify: true }).disable('image')
markdown.validateLink = url => /^https:\/\//i.test(url)
// Parse GitHub comments and HTML before sanitizing the complete rendered document.
const content = computed(() => DOMPurify.sanitize(markdown.render(props.notes), {
  ALLOWED_TAGS: [
    'p', 'br', 'hr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'a', 'em', 'strong', 's',
    'blockquote', 'ul', 'ol', 'li', 'pre', 'code', 'table', 'thead', 'tbody', 'tr', 'th', 'td',
    'details', 'summary',
  ],
  ALLOWED_ATTR: ['href', 'title', 'start', 'open'],
  ALLOWED_URI_REGEXP: /^https:\/\//i,
  ALLOW_DATA_ATTR: false,
  ALLOW_ARIA_ATTR: false,
}))
function openLink(event: MouseEvent) {
  const link = (event.target as HTMLElement).closest<HTMLAnchorElement>('a[href]')
  if (!link) return
  event.preventDefault()
  void openExternal(link.href)
}
</script>

<template>
  <div class="release-markdown" @click="openLink" v-html="content" />
</template>

<style scoped>
.release-markdown { overflow-wrap: anywhere; line-height: 1.7; font-size: 12px; }
.release-markdown :deep(> :first-child) { margin-top: 0; }
.release-markdown :deep(> :last-child) { margin-bottom: 0; }
.release-markdown :deep(h1), .release-markdown :deep(h2), .release-markdown :deep(h3),
.release-markdown :deep(h4), .release-markdown :deep(h5), .release-markdown :deep(h6) { font-size: 14px; font-weight: 600; margin: 18px 0 6px; }
.release-markdown :deep(p), .release-markdown :deep(ul), .release-markdown :deep(ol), .release-markdown :deep(pre), .release-markdown :deep(details) { margin: 8px 0; }
.release-markdown :deep(ul) { list-style: disc; padding-left: 22px; }
.release-markdown :deep(ol) { list-style: decimal; padding-left: 22px; }
.release-markdown :deep(li + li) { margin-top: 4px; }
.release-markdown :deep(a) { color: var(--primary); text-decoration: underline; text-underline-offset: 3px; }
.release-markdown :deep(summary) { cursor: pointer; }
.release-markdown :deep(code) { font-family: ui-monospace, monospace; background: var(--secondary); padding: 1px 4px; border-radius: 3px; }
.release-markdown :deep(pre) { white-space: pre-wrap; background: var(--secondary); padding: 10px; border-radius: 6px; }
.release-markdown :deep(pre code) { padding: 0; }
.release-markdown :deep(blockquote) { border-left: 1px solid var(--border); padding-left: 12px; margin: 12px 0; color: var(--muted); }
.release-markdown :deep(table) { border-collapse: collapse; display: block; overflow: auto; }
.release-markdown :deep(th), .release-markdown :deep(td) { border: 1px solid var(--border); padding: 5px 8px; }
.release-markdown :deep(hr) { border: 0; border-top: 1px solid var(--border); margin: 16px 0; }
</style>
