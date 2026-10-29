import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import QuotaCore

struct ServiceSnapshot {
    var windows: [QuotaWindow] = []
    var lastSuccess: Date?
    var errorMessage: String?
    var refreshing = false
}

@MainActor
final class MonitorModel: ObservableObject {
    static let refreshInterval: TimeInterval = 30
    @Published private(set) var snapshot = ServiceSnapshot()
    @Published var notificationStatus = "正在检查通知权限…"
    @Published var notificationError: String?
    @Published var notificationsEnabled = false
    @Published private(set) var persistentNotificationsEnabled = false
    @Published var showsPersistentNotificationGuide = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchError: String?
    @Published private(set) var showsMenuBar: Bool

    let readsLocalUsage: Bool
    let resetAnnouncements: ResetAnnouncementMonitor
    let updates: AppUpdateModel
    private let defaults: UserDefaults
    private let preferences: ServicePreferences
    private let client: QuotaClient
    private var tracker: ServiceRecoveryTracker
    private var timer: Timer?
    private var schedule = RefreshSchedule()
    private var stopped = false
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var activity: NSObjectProtocol?
    private let stateKey = "recoveryState.v2"
    private let notificationGuideKey = "notifications.persistentGuideShown"

    var monitoringEnabled: Bool { preferences.isEnabled(.codex) }
    var recoveryNotificationsEnabled: Bool { preferences.notificationsEnabled(.codex) }
    var hasMenuBarItem: Bool { showsMenuBar && monitoringEnabled }
    var refreshing: Bool { resetAnnouncements.refreshing || snapshot.refreshing }

    init(defaults: UserDefaults = .standard, client: QuotaClient? = nil) {
        self.defaults = defaults
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
        persistRecovery()
        if enabled { Task { await refresh(force: true) } }
        else { client.stop() }
    }

    func setRecoveryNotificationsEnabled(_ enabled: Bool) {
        objectWillChange.send()
        preferences.setNotificationsEnabled(enabled, for: .codex)
        if enabled { Task { await requestNotificationsIfNeeded() } }
    }

    func setResetNotificationsEnabled(_ enabled: Bool) {
        resetAnnouncements.setNotificationsEnabled(enabled)
        if enabled { Task { await requestNotificationsIfNeeded() } }
    }

    func setShowsMenuBar(_ shown: Bool) {
        showsMenuBar = shown
        defaults.set(shown, forKey: "menuBar.codex.visible")
    }

    private func persistRecovery() {
        if let data = try? JSONEncoder().encode(tracker) { defaults.set(data, forKey: stateKey) }
    }

    func start() {
        stopped = false
        if readsLocalUsage { updates.startAutomaticChecks() }
        resetAnnouncements.setPaused(false)
        // 保持后台定时刷新，仍允许系统正常睡眠。
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "每 30 秒读取 Codex 额度")
        startPolling()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.timer?.invalidate()
                self?.timer = nil
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
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        stopped = true
        resetAnnouncements.stop()
        updates.stopAutomaticChecks()
        timer?.invalidate()
        timer = nil
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
            snapshot = ServiceSnapshot(windows: sample.windows, lastSuccess: Date(), refreshing: true)
            schedule.succeeded()
            let recovered = tracker.observe(service: .codex, account: sample.fingerprint, windows: sample.windows,
                                            notify: recoveryNotificationsEnabled)
            persistRecovery()
            if !recovered.isEmpty { await notifyRecovery(recovered) }
        } catch {
            guard !stopped, monitoringEnabled else { return }
            client.stop()
            let retryAfter = (error as? QuotaHTTPError)?.retryAfter
            let delay = schedule.failed(retryAfter: retryAfter)
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
            notificationStatus = "开启通知后，恢复到 100% 时提醒"
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

    func sendTestNotification() async {
        await requestNotificationsIfNeeded()
        guard notificationsEnabled else { return }
        await sendNotification(title: "额度通知测试", body: "通知已就绪。Codex 实际额度恢复至 100% 时，会在这里提醒。")
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
