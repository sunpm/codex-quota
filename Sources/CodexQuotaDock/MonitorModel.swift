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
    @Published private(set) var services: [QuotaService: ServiceSnapshot] = [:]
    @Published var notificationStatus = "正在检查通知权限…"
    @Published var notificationError: String?
    @Published var notificationsEnabled = false
    @Published private(set) var persistentNotificationsEnabled = false
    @Published var showsPersistentNotificationGuide = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchError: String?
    @Published private(set) var showsMenuBar: Bool

    let readsLocalUsage: Bool
    let cursorUsage: CursorUsageModel
    let resetAnnouncements: ResetAnnouncementMonitor
    private let defaults: UserDefaults
    private let preferences: ServicePreferences
    private let clients: [QuotaService: QuotaClient]
    private var tracker: ServiceRecoveryTracker
    private var timer: Timer?
    private var schedules: [QuotaService: RefreshSchedule] = [:]
    private var requiresManualRetry: Set<QuotaService> = []
    private var stopped = false
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var activity: NSObjectProtocol?
    private let stateKey = "recoveryState.v2"
    private let notificationGuideKey = "notifications.persistentGuideShown"

    var enabledServices: [QuotaService] { QuotaService.allCases.filter { isEnabled($0) } }
    var menuBarServices: [QuotaService] { enabledServices.filter { isShownInMenuBar($0) } }
    var refreshing: Bool { resetAnnouncements.refreshing || enabledServices.contains { snapshot($0).refreshing } }
    var lastSuccess: Date? { enabledServices.compactMap { snapshot($0).lastSuccess }.max() }
    var errorMessage: String? {
        let errors = enabledServices.compactMap { service in snapshot(service).errorMessage.map { "\(service.title)：\($0)" } }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }
    var notificationServiceCount: Int { enabledServices.filter { notificationsEnabled(for: $0) }.count }
    func snapshot(_ service: QuotaService) -> ServiceSnapshot { services[service] ?? ServiceSnapshot() }
    func isEnabled(_ service: QuotaService) -> Bool { preferences.isEnabled(service) }
    func notificationsEnabled(for service: QuotaService) -> Bool { preferences.notificationsEnabled(service) }
    func isShownInMenuBar(_ service: QuotaService) -> Bool { preferences.isShownInMenuBar(service) }

    init(defaults: UserDefaults = .standard, clients: [QuotaService: QuotaClient]? = nil) {
        self.defaults = defaults
        showsMenuBar = defaults.object(forKey: "menuBar.visible") as? Bool ?? true
        readsLocalUsage = clients == nil
        preferences = ServicePreferences(defaults: defaults)
        let resolvedClients = clients ?? [.codex: CodexClient(), .claude: ClaudeClient(), .antigravity: AntigravityClient(), .cursor: CursorClient()]
        self.clients = resolvedClients
        cursorUsage = CursorUsageModel(client: resolvedClients[.cursor] as? CursorClient, enabled: preferences.isEnabled(.cursor))
        resetAnnouncements = ResetAnnouncementMonitor(defaults: defaults, enabled: preferences.isEnabled(.codex),
                                                       client: clients == nil ? ResetAnnouncementClient() : nil)
        if let data = defaults.data(forKey: stateKey), let saved = try? JSONDecoder().decode(ServiceRecoveryTracker.self, from: data) {
            tracker = saved
        } else {
            let legacy = defaults.data(forKey: "recoveryState.v1").flatMap { try? JSONDecoder().decode(RecoveryState.self, from: $0) }
            tracker = ServiceRecoveryTracker(states: legacy.map { [QuotaService.codex.rawValue: $0] } ?? [:])
        }
        for service in QuotaService.allCases where !preferences.isEnabled(service) { tracker.clear(service) }
    }

    func setEnabled(_ enabled: Bool, for service: QuotaService) {
        objectWillChange.send()
        preferences.setEnabled(enabled, for: service)
        if service == .cursor { cursorUsage.setEnabled(enabled) }
        if service == .codex {
            resetAnnouncements.setEnabled(enabled)
            if enabled { Task { await refreshResetAnnouncements() } }
        }
        // 停止监测时没有连续观测；再次开启先建立基线。
        tracker.clear(service)
        persistRecovery()
        if service == .codex, !enabled { clients[service]?.stop() }
        if enabled { Task { await refresh(service, force: true) } }
    }

    func setNotificationsEnabled(_ enabled: Bool, for service: QuotaService) {
        objectWillChange.send()
        preferences.setNotificationsEnabled(enabled, for: service)
        if enabled { Task { await requestNotificationsIfNeeded() } }
    }

    func setResetNotificationsEnabled(_ enabled: Bool) {
        resetAnnouncements.setNotificationsEnabled(enabled)
        if enabled { Task { await requestNotificationsIfNeeded() } }
    }

    func setShowsMenuBar(_ shown: Bool) {
        showsMenuBar = shown
        defaults.set(shown, forKey: "menuBar.visible")
    }

    func setShownInMenuBar(_ shown: Bool, for service: QuotaService) {
        objectWillChange.send()
        preferences.setShownInMenuBar(shown, for: service)
    }

    private func persistRecovery() {
        if let data = try? JSONEncoder().encode(tracker) { defaults.set(data, forKey: stateKey) }
    }

    func start() {
        stopped = false
        resetAnnouncements.setPaused(false)
        // 保持后台定时刷新，仍允许系统正常睡眠。
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "每 30 秒读取已启用服务的额度")
        startPolling()
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.timer?.invalidate()
                self?.timer = nil
                self?.cursorUsage.setPaused(true)
                self?.resetAnnouncements.setPaused(true)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.startPolling()
                self?.cursorUsage.setPaused(false)
                self?.resetAnnouncements.setPaused(false)
                await self?.refresh(force: true, retryCredentials: false)
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
        cursorUsage.setPaused(true)
        resetAnnouncements.stop()
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        for client in clients.values { client.stop() }
    }

    func refresh(force: Bool = false, retryCredentials: Bool = true) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshResetAnnouncements() }
            for service in enabledServices {
                group.addTask { await self.refresh(service, force: force, retryCredentials: retryCredentials) }
            }
        }
    }

    private func refreshResetAnnouncements() async {
        let events = await resetAnnouncements.refresh()
        guard !events.isEmpty else { return }
        await updateNotificationStatus()
        for event in events {
            guard !stopped, isEnabled(.codex), notificationsEnabled, resetAnnouncements.notificationsEnabled else { return }
            if let post = event.latestPost {
                await sendNotification(title: event.notificationTitle, body: post.text,
                                       identifier: "reset-announcement:\(post.id):\(event.status.rawValue)", resetPostID: post.id)
            }
        }
    }

    private func refresh(_ service: QuotaService, force: Bool, retryCredentials: Bool = true) async {
        guard !stopped, isEnabled(service), !snapshot(service).refreshing,
              (force && retryCredentials) || !requiresManualRetry.contains(service),
              schedules[service, default: RefreshSchedule()].canRefresh(force: force), let client = clients[service] else { return }
        requiresManualRetry.remove(service)
        services[service, default: ServiceSnapshot()].refreshing = true
        defer { services[service, default: ServiceSnapshot()].refreshing = false }
        do {
            let sample = try await client.sample()
            guard !stopped, isEnabled(service) else { return }
            if service == .cursor { cursorUsage.observeAccount(sample.fingerprint) }
            services[service] = ServiceSnapshot(windows: sample.windows, lastSuccess: Date(), refreshing: true)
            schedules[service, default: RefreshSchedule()].succeeded()
            let recovered = tracker.observe(service: service, account: sample.fingerprint, windows: sample.windows,
                                            notify: notificationsEnabled(for: service))
            persistRecovery()
            if !recovered.isEmpty { await notifyRecovery(recovered, service: service) }
        } catch {
            guard !stopped, isEnabled(service) else { return }
            if service == .codex { client.stop() }
            if error is KeychainAccessDeclined {
                requiresManualRetry.insert(service)
                services[service, default: ServiceSnapshot()].errorMessage = error.localizedDescription
                return
            }
            let retryAfter = (error as? QuotaHTTPError)?.retryAfter
            let delay = schedules[service, default: RefreshSchedule()].failed(retryAfter: retryAfter)
            services[service, default: ServiceSnapshot()].errorMessage = "\(error.localizedDescription) \(Int(min(delay, Double(Int.max / 2)))) 秒后重试。"
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

    private func notifyRecovery(_ recovered: [QuotaWindow], service: QuotaService) async {
        await updateNotificationStatus()
        guard !stopped, isEnabled(service), notificationsEnabled, notificationsEnabled(for: service) else { return }
        let descriptions = recovered.map(\.displayLabel)
        await sendNotification(title: "\(service.title) 额度已恢复至 100%", body: descriptions.joined(separator: "、") + "已恢复，可以继续使用。")
    }

    func sendTestNotification() async {
        await requestNotificationsIfNeeded()
        guard notificationsEnabled else { return }
        await sendNotification(title: "额度通知测试", body: "通知已就绪。启用提醒的服务在实际额度恢复至 100% 时，会在这里通知。")
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
