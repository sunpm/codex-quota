import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import QuotaCore

@MainActor
final class MonitorModel: ObservableObject {
    @Published var windows: [QuotaWindow] = []
    @Published var lastSuccess: Date?
    @Published var errorMessage: String?
    @Published var refreshing = false
    @Published var notificationStatus = "正在检查通知权限…"
    @Published var notificationError: String?
    @Published var notificationsEnabled = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchError: String?
    @Published var selectedWindowID: String {
        didSet { defaults.set(selectedWindowID, forKey: "selectedWindowID"); updateDock() }
    }

    private let defaults: UserDefaults
    private let client = CodexClient()
    private var tracker: RecoveryTracker
    private var timer: Timer?
    private var nextAttempt = Date.distantPast
    private var failures = 0
    private var stopped = false
    private var wakeObserver: NSObjectProtocol?
    private var activity: NSObjectProtocol?
    private let stateKey = "recoveryState.v1"

    var selectedWindow: QuotaWindow? {
        windows.first { $0.id == selectedWindowID }
            ?? windows.filter { $0.bucket == "codex" }.min { $0.remaining < $1.remaining }
            ?? windows.first
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedWindowID = defaults.string(forKey: "selectedWindowID") ?? ""
        let saved = defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(RecoveryState.self, from: $0) }
        tracker = RecoveryTracker(state: saved)
    }

    func start() {
        stopped = false
        // 保持后台定时刷新，仍允许系统正常睡眠。
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "每 30 秒读取 Codex 额度")
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer?.tolerance = 1
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: true) }
        }
        Task {
            await refresh(force: true)
            await requestNotificationsIfNeeded()
        }
    }

    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        client.stop()
    }

    func refresh(force: Bool = false) async {
        guard !stopped, !refreshing, force || Date() >= nextAttempt else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let sample = try await client.sample()
            guard !stopped else { return }
            windows = sample.windows
            lastSuccess = Date()
            errorMessage = nil
            failures = 0
            nextAttempt = .distantPast
            let recovered = tracker.observe(account: sample.fingerprint, windows: sample.windows)
            if let state = tracker.state, let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: stateKey) }
            updateDock()
            if !recovered.isEmpty { await notifyRecovery(recovered) }
        } catch {
            guard !stopped else { return }
            client.stop()
            failures += 1
            let delay = min(300, 30 * pow(2, Double(min(failures - 1, 4))))
            nextAttempt = Date().addingTimeInterval(delay)
            errorMessage = "\(error.localizedDescription) \(Int(delay)) 秒后重试。"
            updateDock()
        }
    }

    func updateDock() {
        let value = selectedWindow?.percentageText ?? "—"
        NSApp.dockTile.badgeLabel = errorMessage == nil ? value : "\(value) !"
        NSApp.dockTile.display()
    }

    func updateNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsEnabled = true
            notificationStatus = "额度恢复到 100% 时通知一次"
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
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    private func notifyRecovery(_ recovered: [QuotaWindow]) async {
        await updateNotificationStatus()
        guard notificationsEnabled else { return }
        let descriptions = recovered.map { "\($0.name == "codex" ? "Codex" : $0.name) · \($0.periodText)" }
        await sendNotification(title: "Codex 额度已恢复至 100%", body: descriptions.joined(separator: "、") + "已恢复，可以继续使用。")
    }

    func sendTestNotification() async {
        await requestNotificationsIfNeeded()
        guard notificationsEnabled else { return }
        await sendNotification(title: "Codex 额度通知测试", body: "通知已就绪。实际额度从不足 100% 恢复至 100% 时，会在这里提醒。")
    }

    private func sendNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
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
