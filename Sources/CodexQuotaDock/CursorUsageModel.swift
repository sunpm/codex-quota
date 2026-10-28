import Foundation
import SwiftUI
import QuotaCore

struct CursorUsageSnapshot {
    let events: [CursorUsageEvent]
    let interval: DateInterval
    let updatedAt: Date
}

@MainActor
final class CursorUsageModel: ObservableObject {
    @Published private(set) var snapshot: CursorUsageSnapshot?
    @Published private(set) var refreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var enabled: Bool
    @Published var startDate = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))!
    @Published var endDate = Calendar.current.startOfDay(for: Date())
    private let client: CursorClient?
    private var account: String?
    private var schedule = RefreshSchedule()
    private var nextRefresh = Date.distantPast
    private var requestedInterval: DateInterval?
    private var requiresManualRetry = false
    private var paused = false
    private var generation = 0
    private var task: Task<Void, Never>?

    var interval: DateInterval {
        let calendar = Calendar.current
        return DateInterval(start: calendar.startOfDay(for: startDate),
                            end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!)
    }

    init(client: CursorClient?, enabled: Bool) {
        self.client = client
        self.enabled = enabled
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value {
            cancel()
            snapshot = nil
            account = nil
        }
        nextRefresh = .distantPast
    }

    func setPaused(_ value: Bool) {
        paused = value
        if value { cancel() }
    }

    func observeAccount(_ fingerprint: String) {
        guard account != fingerprint else { return }
        if account != nil { cancel() }
        account = fingerprint
        snapshot = nil
        errorMessage = nil
        requiresManualRetry = false
        nextRefresh = .distantPast
    }

    private func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        refreshing = false
    }

    func refresh(force: Bool = false) async {
        let selected = interval
        if requestedInterval != selected {
            cancel()
            requestedInterval = selected
            nextRefresh = .distantPast
        }
        guard enabled, !paused, !refreshing, let client,
              force || !requiresManualRetry,
              force || Date() >= nextRefresh,
              schedule.canRefresh(force: force) else { return }
        guard Date() >= client.rateLimitedUntil else {
            errorMessage = "Cursor 请求正在限流冷却，稍后自动重试。"
            return
        }
        requiresManualRetry = false
        nextRefresh = .distantPast
        refreshing = true
        generation += 1
        let requestGeneration = generation
        let interval = DateInterval(start: selected.start, end: min(selected.end, Date()))
        task = Task {
            defer {
                if generation == requestGeneration { refreshing = false; task = nil }
            }
            do {
                let auth = try await Task.detached(priority: .utility) { try LocalCredentials.cursorSession() }.value
                try Task.checkCancellation()
                let fingerprint = accountFingerprint(auth.subject)
                if account != fingerprint {
                    account = fingerprint
                    snapshot = nil
                }
                let events = try await client.usage(auth: auth, interval: interval)
                try Task.checkCancellation()
                snapshot = CursorUsageSnapshot(events: events, interval: interval, updatedAt: Date())
                errorMessage = nil
                schedule.succeeded()
                nextRefresh = Date().addingTimeInterval(300)
            } catch {
                guard !Task.isCancelled, generation == requestGeneration else { return }
                if error is KeychainAccessDeclined { requiresManualRetry = true }
                let http = error as? QuotaHTTPError
                if http?.status == 401 || http?.status == 403 { requiresManualRetry = true }
                let delay = schedule.failed(retryAfter: http?.retryAfter)
                let message = http.map { "Cursor 用量请求失败（HTTP \($0.status)）。" } ?? error.localizedDescription
                errorMessage = message + (requiresManualRetry
                    ? " 请确认登录与访问权限后手动刷新。"
                    : " \(Int(min(delay, Double(Int.max / 2)))) 秒后重试。")
            }
        }
        await task?.value
    }
}
