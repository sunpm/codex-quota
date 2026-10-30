import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import QuotaCore

struct ServiceSnapshot {
    var windows: [QuotaWindow] = []
    var resetCredits: RateLimitResetCredits?
    var lastSuccess: Date?
    var errorMessage: String?
    var refreshing = false
}

@MainActor
final class MonitorModel: ObservableObject {
    @Published private(set) var refreshInterval: Int
    @Published private(set) var snapshot = ServiceSnapshot()
    @Published private(set) var quotaHistory = QuotaHistory()
    @Published var notificationStatus = "正在检查通知权限…"
    @Published var notificationError: String?
    @Published var notificationsEnabled = false
    @Published private(set) var persistentNotificationsEnabled = false
    @Published var showsPersistentNotificationGuide = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchError: String?
    @Published private(set) var showsMenuBar: Bool
    @Published private(set) var animationsEnabled: Bool
    @Published private(set) var resetCreditRemindersEnabled: Bool

    let readsLocalUsage: Bool
    let resetAnnouncements: ResetAnnouncementMonitor
    let updates: AppUpdateModel
    private let defaults: UserDefaults
    private let preferences: ServicePreferences
    private let client: QuotaClient
    private var tracker: ServiceRecoveryTracker
    private var timer: Timer?
    private var announcementTimer: Timer?
    private var schedule = RefreshSchedule()
    private var stopped = false
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var activity: NSObjectProtocol?
    private let stateKey = "recoveryState.v2"
    private let quotaHistoryKey = "quotaHistory.v1"
    private var continuousQuotaObservation = false
    private let notificationGuideKey = "notifications.persistentGuideShown"
    private let resetCreditRemindersKey = "resetCredits.expirationReminders"
    private let resetCreditReminderStateKey = "resetCredits.reminded.v1"
    private var remindedResetCredits: [String: Date]

    var monitoringEnabled: Bool { preferences.isEnabled(.codex) }
    var recoveryNotificationsEnabled: Bool { preferences.notificationsEnabled(.codex) }
    var hasMenuBarItem: Bool { showsMenuBar && monitoringEnabled }

    init(defaults: UserDefaults = .standard, client: QuotaClient? = nil) {
        self.defaults = defaults
        resetCreditRemindersEnabled = defaults.bool(forKey: resetCreditRemindersKey)
        remindedResetCredits = defaults.data(forKey: resetCreditReminderStateKey)
            .flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        refreshInterval = max(30, defaults.object(forKey: "quota.refreshIntervalSeconds") as? Int ?? 300)
        animationsEnabled = defaults.object(forKey: "appearance.animationsEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: quotaHistoryKey),
           let saved = try? JSONDecoder().decode(QuotaHistory.self, from: data) {
            quotaHistory = saved
        }
        preferences = ServicePreferences(defaults: defaults)
        showsMenuBar = defaults.object(forKey: "menuBar.codex.visible") as? Bool
            ?? ((defaults.object(forKey: "menuBar.visible") as? Bool ?? true) && preferences.isShownInMenuBar(.codex))
        readsLocalUsage = client == nil
        updates = AppUpdateModel(defaults: defaults)
        self.client = client ?? CodexClient()
        resetAnnouncements = ResetAnnouncementMonitor(defaults: defaults, enabled: preferences.isEnabled(.codex),
                                                       client: client == nil ? ResetAnnouncementClient() : nil)
        if let data = defaults.data(forKey: stateKey), let saved = try? JSONDecoder().decode(ServiceRecoveryTracker.self, from: data) {
            tracker = saved
        } else {
            let legacy = defaults.data(forKey: "recoveryState.v1").flatMap { try? JSONDecoder().decode(RecoveryState.self, from: $0) }
            tracker = ServiceRecoveryTracker(states: legacy.map { [QuotaService.codex.rawValue: $0] } ?? [:])
        }
        if !monitoringEnabled { tracker.clear(.codex) }
    }

    func setMonitoringEnabled(_ enabled: Bool) {
        objectWillChange.send()
        preferences.setEnabled(enabled, for: .codex)
        resetAnnouncements.setEnabled(enabled)
        // 停止监测时没有连续观测；再次开启先建立基线。
        tracker.clear(.codex)
        continuousQuotaObservation = false
        persistRecovery()
        if enabled { Task { await refresh(force: true) } }
        else { client.stop() }
    }

    func setRecoveryNotificationsEnabled(_ enabled: Bool) {
        objectWillChange.send()
        preferences.setNotificationsEnabled(enabled, for: .codex)
        if enabled { Task { await requestNotificationsIfNeeded() } }
    }

    func setRefreshInterval(_ seconds: Int) {
        let seconds = max(30, seconds)
        guard seconds != refreshInterval else { return }
        refreshInterval = seconds
        defaults.set(seconds, forKey: "quota.refreshIntervalSeconds")
        if timer != nil { startPolling() }
    }

    func setResetNotificationsEnabled(_ enabled: Bool) {
        resetAnnouncements.setNotificationsEnabled(enabled)
        if enabled { Task { await requestNotificationsIfNeeded() } }
    }

    func setResetCreditRemindersEnabled(_ enabled: Bool) {
        resetCreditRemindersEnabled = enabled
        defaults.set(enabled, forKey: resetCreditRemindersKey)
        if enabled { Task { await requestNotificationsIfNeeded() } }
    }

    func setShowsMenuBar(_ shown: Bool) {
        showsMenuBar = shown
        defaults.set(shown, forKey: "menuBar.codex.visible")
    }

    func setAnimationsEnabled(_ enabled: Bool) {
        animationsEnabled = enabled
        defaults.set(enabled, forKey: "appearance.animationsEnabled")
    }

    private func persistRecovery() {
        if let data = try? JSONEncoder().encode(tracker) { defaults.set(data, forKey: stateKey) }
    }

    func start() {
        stopped = false
        if readsLocalUsage { updates.startAutomaticChecks() }
        resetAnnouncements.setPaused(false)
        // 保持后台定时刷新，仍允许系统正常睡眠。
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "定时读取 Codex 额度")
        startPolling()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.timer?.invalidate()
                self?.timer = nil
                self?.announcementTimer?.invalidate()
                self?.announcementTimer = nil
                self?.continuousQuotaObservation = false
                self?.resetAnnouncements.setPaused(true)
                self?.updates.stopAutomaticChecks()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.startPolling()
                self?.resetAnnouncements.setPaused(false)
                if self?.readsLocalUsage == true { self?.updates.startAutomaticChecks() }
                await self?.refresh(force: true)
            }
        }
        Task { await refresh(force: true) }
        Task { await requestNotificationsIfNeeded() }
    }

    private func startPolling() {
        guard !stopped else { return }
        timer?.invalidate()
        let nextRefresh = schedule.failures > 0
            ? max(Date(), schedule.nextAttempt)
            : Date().addingTimeInterval(TimeInterval(refreshInterval))
        let timer = Timer(fire: nextRefresh, interval: TimeInterval(refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshQuota(force: false) }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // 公开动态沿用自己的请求间隔，不受额度刷新设置影响。
        if announcementTimer == nil {
            let announcementTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.refreshResetAnnouncements() }
            }
            announcementTimer.tolerance = 0.3
            RunLoop.main.add(announcementTimer, forMode: .common)
            self.announcementTimer = announcementTimer
        }
    }

    func stop() {
        stopped = true
        continuousQuotaObservation = false
        resetAnnouncements.stop()
        updates.stopAutomaticChecks()
        timer?.invalidate()
        timer = nil
        announcementTimer?.invalidate()
        announcementTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        client.stop()
    }

    func refresh(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshResetAnnouncements() }
            group.addTask { await self.refreshQuota(force: force) }
        }
    }

    private func refreshResetAnnouncements() async {
        let events = await resetAnnouncements.refresh()
        guard !events.isEmpty else { return }
        await updateNotificationStatus()
        for event in events {
            guard !stopped, monitoringEnabled, notificationsEnabled, resetAnnouncements.notificationsEnabled else { return }
            if let post = event.latestPost {
                await sendNotification(title: event.notificationTitle, body: post.text,
                                       identifier: "reset-announcement:\(post.id):\(event.status.rawValue)", resetPostID: post.id)
            }
        }
    }

    private func refreshQuota(force: Bool) async {
        guard !stopped, monitoringEnabled, !snapshot.refreshing, schedule.canRefresh(force: force) else { return }
        snapshot.refreshing = true
        defer { snapshot.refreshing = false }
        do {
            let sample = try await client.sample()
            guard !stopped, monitoringEnabled else { return }
            let now = Date()
            quotaHistory.observe(account: sample.fingerprint, windows: sample.windows, at: now,
                                 continuous: continuousQuotaObservation, maximumGap: TimeInterval(refreshInterval) * 3)
            continuousQuotaObservation = true
            if let data = try? JSONEncoder().encode(quotaHistory) {
                defaults.set(data, forKey: quotaHistoryKey)
            }
            snapshot = ServiceSnapshot(windows: sample.windows, resetCredits: sample.resetCredits,
                                       lastSuccess: now, refreshing: true)
            schedule.succeeded()
            timer?.fireDate = now.addingTimeInterval(TimeInterval(refreshInterval))
            let recovered = tracker.observe(service: .codex, account: sample.fingerprint, windows: sample.windows,
                                            notify: recoveryNotificationsEnabled)
            persistRecovery()
            await notifyExpiringResetCredits(sample, at: now)
            if !recovered.isEmpty { await notifyRecovery(recovered) }
        } catch {
            guard !stopped, monitoringEnabled else { return }
            continuousQuotaObservation = false
            client.stop()
            let retryAfter = (error as? QuotaHTTPError)?.retryAfter
            let delay = schedule.failed(retryAfter: retryAfter)
            timer?.fireDate = schedule.nextAttempt
            snapshot.errorMessage = "\(error.localizedDescription) \(Int(min(delay, Double(Int.max / 2)))) 秒后重试。"
        }
    }

    func updateNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        persistentNotificationsEnabled = false
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsEnabled = true
            switch settings.alertSetting {
            case .enabled:
                switch settings.alertStyle {
                case .alert:
                    persistentNotificationsEnabled = true
                    notificationStatus = "持久通知已开启，提醒保留到手动关闭"
                case .banner:
                    notificationStatus = "临时横幅，提醒会自动消失"
                case .none:
                    notificationStatus = "已允许通知，未开启桌面提醒"
                @unknown default:
                    notificationStatus = "已允许通知，无法确认提醒样式"
                }
            case .disabled:
                notificationStatus = "已允许通知，未开启桌面提醒"
            case .notSupported:
                notificationStatus = "已允许通知，无法确认提醒样式"
            @unknown default:
                notificationStatus = "已允许通知，无法确认提醒样式"
            }
        case .denied:
            notificationsEnabled = false
            notificationStatus = "通知未获允许，请在系统设置中开启"
        case .notDetermined:
            notificationsEnabled = false
            notificationStatus = "尚未允许系统通知"
        @unknown default:
            notificationsEnabled = false
            notificationStatus = "无法确认通知权限"
        }
    }

    func requestNotificationsIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { notificationError = "申请通知权限失败：\(error.localizedDescription)" }
        } else if settings.authorizationStatus == .denied {
            await updateNotificationStatus()
            return
        }
        await updateNotificationStatus()
        if settings.authorizationStatus == .notDetermined, notificationsEnabled,
           !persistentNotificationsEnabled, !defaults.bool(forKey: notificationGuideKey) {
            showPersistentNotificationGuide()
        }
    }

    func showPersistentNotificationGuide() {
        defaults.set(true, forKey: notificationGuideKey)
        showsPersistentNotificationGuide = true
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    private func notifyRecovery(_ recovered: [QuotaWindow]) async {
        await updateNotificationStatus()
        guard !stopped, monitoringEnabled, notificationsEnabled, recoveryNotificationsEnabled else { return }
        let descriptions = recovered.map(\.displayLabel)
        await sendNotification(title: "Codex 额度已恢复至 100%", body: descriptions.joined(separator: "、") + "已恢复，可以继续使用。")
    }

    private func notifyExpiringResetCredits(_ sample: QuotaSample, at now: Date) async {
        remindedResetCredits = remindedResetCredits.filter { $0.value > now }
        var expiring: [Date] = []
        for credit in sample.resetCredits?.availableCredits ?? [] {
            guard let expiration = credit.expirationDate, expiration > now,
                  expiration.timeIntervalSince(now) <= 24 * 60 * 60 else { continue }
            let key = accountFingerprint("\(sample.fingerprint):\(credit.id)")
            guard remindedResetCredits[key] == nil else { continue }
            // 关闭提醒期间也消费事件，避免再次开启后补发。
            remindedResetCredits[key] = expiration
            expiring.append(expiration)
        }
        if let data = try? JSONEncoder().encode(remindedResetCredits) {
            defaults.set(data, forKey: resetCreditReminderStateKey)
        }
        guard resetCreditRemindersEnabled, let earliest = expiring.min() else { return }
        await updateNotificationStatus()
        guard !stopped, monitoringEnabled, notificationsEnabled, resetCreditRemindersEnabled else { return }
        let date = earliest.formatted(.dateTime.month().day().hour().minute())
        let body = expiring.count == 1 ? "1 张重置卡将于 \(date) 到期。"
            : "\(expiring.count) 张重置卡将在 24 小时内到期，最早于 \(date) 到期。"
        await sendNotification(title: "Codex 重置卡即将到期", body: body)
    }

    func sendTestNotification() async {
        await requestNotificationsIfNeeded()
        guard notificationsEnabled else { return }
        await sendNotification(title: "Codex 通知测试", body: "通知已就绪，将按设置发送额度恢复、重置卡到期或重置动态提醒。")
    }

    private func sendNotification(title: String, body: String, identifier: String = UUID().uuidString, resetPostID: String? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let resetPostID { content.userInfo["resetPostID"] = resetPostID }
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            notificationError = nil
        } catch { notificationError = "通知发送失败：\(error.localizedDescription)" }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许此应用。" : nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = "设置失败。请将应用移入“应用程序”后重试：\(error.localizedDescription)"
        }
    }
}
