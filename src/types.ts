export type Page = 'overview' | 'details' | 'quota' | 'settings'
export type Metric = 'tokens' | 'cost'
export type UsageService = 'codex' | 'antigravity'
export type QuotaService = UsageService | 'all'
export interface ChartTimeHover { timestamp: number; tolerance: number }
export interface NotificationStatus {
  permission: 'system' | 'granted' | 'denied' | 'prompt'
  alertStyle: 'persistent' | 'banner' | 'disabled' | 'unknown'
}
export interface Settings {
  monitoringEnabled: boolean
  antigravityEnabled: boolean
  antigravityAnnouncementNotifications: boolean
  antigravityShowTray: boolean
  recoveryNotifications: boolean
  resetCreditReminders: boolean
  resetCreditReminderMinutes: number[]
  quotaResetReminders: boolean
  quotaResetReminderMinutes: number[]
  announcementNotifications: boolean
  showTray: boolean
  launchAtLogin: boolean
  animations: boolean
  refreshInterval: number
  automaticUpdates: boolean
  todayMetrics: string[]
  detailColumns: string[]
}
export interface UsageTokens { input: number; output: number; cached: number; cacheWrite: number; cacheWriteLong: number; cacheWriteReported?: boolean | null; inputReported?: boolean | null; outputReported?: boolean | null; cachedReported?: boolean | null }
export interface UsageRecord {
  id: string; service: string; session: string; project: string; model: string; date: number
  tokens: UsageTokens; serviceTier: string; isUSOnly: boolean; serviceTierReported?: boolean | null
  estimatedDuration?: number | null; estimatedFirstToken?: number | null; cost: string | null
}
export interface CostComponent { kind: 'input' | 'output' | 'cached' | 'cacheWrite' | 'cacheWriteLong'; tokens: number; rate: string | null; amount: string | null }
export interface CostBreakdown {
  pricingModel: string | null; longContext: boolean; contextThreshold: number | null
  multiplier: string | null; components: CostComponent[]; total: string | null
}
export interface TokenRates { input: string | null; output: string | null; cached: string | null; cacheWrite: string | null; cacheWriteLong: string | null }
export interface ModelPricing {
  service: string; model: string; rates: TokenRates; contextThreshold: number | null
  longContextRates: TokenRates | null; fastMultiplier: string | null; ultrafastMultiplier: string | null; custom?: boolean
}
export interface QuotaWindow { id: string; bucket: string; name: string; usedPercent: number; durationMinutes: number | null; resetsAt: number | null; label: string | null }
export interface ResetCredit { id: string; resetType: string; status: string; expiresAt: number | null }
export interface QuotaSeries { window: QuotaWindow; points: { date: number; usedPercent: number; segment: number }[] }
export interface Announcement {
  id: string; type: string; displayLabel: string | null; status: string
  presentation: { status: string; scopeLabel: string | null } | null
  confirmedAt: number | null; confirmationBasis: string | null
  schedule: { through: number; label: string } | null; estimate: { through: number; label: string } | null
  updatedAt: number; posts: { id: string; publishedAt: number; text: string; url: string }[]
}
export interface AntigravityBucket { id: string; name: string; window: string | null; remainingPercent: number | null; resetsAt: number | null; disabled: boolean }
export interface AntigravityGroup { name: string; buckets: AntigravityBucket[] }
export interface AnnouncementSnapshot { events: Announcement[]; error: string | null; sourceStatus: string | null; refreshing: boolean; lastSuccess: number | null }
export interface UpdateState {
  status: 'idle' | 'checking' | 'available' | 'current' | 'downloading' | 'installing' | 'error'
  version: string | null; notes: string | null; error: string | null; progress: number | null; canInstall: boolean
}
export interface AppSnapshot {
  error?: string | null
  settings: Settings
  quota: { windows: QuotaWindow[]; resetCredits: { availableCount: number; credits: ResetCredit[] | null } | null; history: Record<string, QuotaSeries>; error: string | null; lastSuccess: number | null; refreshing: boolean }
  announcements: AnnouncementSnapshot
  antigravity: { groups: AntigravityGroup[]; error: string | null; lastSuccess: number | null; refreshing: boolean; requiresAction: boolean }
  antigravityAnnouncements: AnnouncementSnapshot
  usage: { records: UsageRecord[]; projectRoots: Record<string, string>; sessionTitles: Record<string, string>; warnings: string[]; scannedAt: number | null; fileCount: number; refreshing: boolean; source: string }
  prices: ModelPricing[]
  priceDate: string
  version: string
  platform: string
  update: UpdateState
  installedReleaseNotes: string | null
  notificationGuideShown: boolean
}
