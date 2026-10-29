import Foundation
import SwiftUI
import QuotaCore

@MainActor
final class ResetAnnouncementMonitor: ObservableObject {
    static let refreshInterval: TimeInterval = 600
    @Published private(set) var feed: ResetAnnouncementFeed?
    @Published private(set) var refreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var notificationsEnabled: Bool
    @Published private(set) var enabled: Bool

    private struct SavedState: Codable {
        var feed: ResetAnnouncementFeed?
        var etag: String?
        var tracker = ResetAnnouncementTracker()
        var nextRequest = Date.distantPast
    }
    private let defaults: UserDefaults
    private let client: ResetAnnouncementClient?
    private let stateKey = "resetAnnouncements.state.v1"
    private let notificationsKey = "resetAnnouncements.notifications"
    private var state: SavedState
    private var paused = false
    private var task: Task<[ResetAnnouncement], Never>?

    init(defaults: UserDefaults, enabled: Bool, client: ResetAnnouncementClient?) {
        self.defaults = defaults
        self.enabled = enabled
        self.client = client
        notificationsEnabled = defaults.bool(forKey: notificationsKey)
        state = defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) } ?? SavedState()
        feed = state.feed
        if !enabled { state.tracker.hasBaseline = false }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value {
            task?.cancel()
            state.tracker.hasBaseline = false
            persist()
        }
    }

    func setNotificationsEnabled(_ value: Bool) {
        notificationsEnabled = value
        defaults.set(value, forKey: notificationsKey)
    }

    func setPaused(_ value: Bool) {
        paused = value
        if value { task?.cancel() }
    }

    func stop() {
        setPaused(true)
        client?.stop()
    }

    func refresh() async -> [ResetAnnouncement] {
        guard enabled, !paused, !refreshing, Date() >= state.nextRequest, let client else { return [] }
        refreshing = true
        // 手动、唤醒及重启均沿用同一请求间隔；不绕过上游采集周期和冷却。
        state.nextRequest = Date().addingTimeInterval(Self.refreshInterval)
        persist()
        let request = Task { () -> [ResetAnnouncement] in
            defer { refreshing = false; task = nil }
            do {
                let response = try await client.fetch(etag: state.feed == nil ? nil : state.etag)
                try Task.checkCancellation()
                switch response {
                case .updated(let snapshot, let etag):
                    state.feed = snapshot
                    state.etag = etag
                    feed = snapshot
                case .notModified:
                    guard state.feed != nil else { throw MonitorError.message("AIHOT 未返回首次快照。") }
                }
                let notifications = state.tracker.observe(state.feed?.events ?? [], notify: notificationsEnabled)
                errorMessage = nil
                persist()
                return notifications
            } catch {
                guard !Task.isCancelled else { return [] }
                let http = error as? QuotaHTTPError
                if let delay = http?.retryAfter {
                    state.nextRequest = max(state.nextRequest, Date().addingTimeInterval(delay))
                }
                if let http { errorMessage = "AIHOT 请求失败（HTTP \(http.status)），稍后自动重试。" }
                else if error is DecodingError { errorMessage = "AIHOT 数据格式暂不兼容。" }
                else { errorMessage = "无法读取 AIHOT 动态，请检查网络。" }
                persist()
                return []
            }
        }
        task = request
        return await request.value
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: stateKey) }
    }
}
