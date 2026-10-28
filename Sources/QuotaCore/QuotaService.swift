import Foundation

public enum QuotaService: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex, claude, antigravity, cursor

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .antigravity: return "Antigravity"
        case .cursor: return "Cursor"
        }
    }
    public var vendor: String {
        switch self {
        case .codex: return "OpenAI"
        case .claude: return "Anthropic"
        case .antigravity: return "Google"
        case .cursor: return "Anysphere"
        }
    }
    public var symbol: String {
        switch self {
        case .codex: return "terminal"
        case .claude: return "asterisk"
        case .antigravity: return "sparkles"
        case .cursor: return "cursorarrow"
        }
    }
}

public struct ServicePreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    public func isEnabled(_ service: QuotaService) -> Bool {
        defaults.object(forKey: "service.\(service.rawValue).enabled") as? Bool ?? true
    }
    public func notificationsEnabled(_ service: QuotaService) -> Bool {
        defaults.object(forKey: "service.\(service.rawValue).notifications") as? Bool ?? true
    }
    public func isShownInMenuBar(_ service: QuotaService) -> Bool {
        defaults.object(forKey: "service.\(service.rawValue).menuBar") as? Bool ?? true
    }
    public func setEnabled(_ enabled: Bool, for service: QuotaService) {
        defaults.set(enabled, forKey: "service.\(service.rawValue).enabled")
    }
    public func setNotificationsEnabled(_ enabled: Bool, for service: QuotaService) {
        defaults.set(enabled, forKey: "service.\(service.rawValue).notifications")
    }
    public func setShownInMenuBar(_ shown: Bool, for service: QuotaService) {
        defaults.set(shown, forKey: "service.\(service.rawValue).menuBar")
    }
}

/// 每个服务独立保存账号与窗口基线；通知关闭期间也消费恢复事件。
public struct ServiceRecoveryTracker: Codable {
    public private(set) var states: [String: RecoveryState]
    public init(states: [String: RecoveryState] = [:]) { self.states = states }

    public mutating func observe(service: QuotaService, account: String, windows: [QuotaWindow], notify: Bool) -> [QuotaWindow] {
        var tracker = RecoveryTracker(state: states[service.rawValue])
        let recovered = tracker.observe(account: account, windows: windows)
        states[service.rawValue] = tracker.state
        return notify ? recovered : []
    }

    public mutating func clear(_ service: QuotaService) { states[service.rawValue] = nil }
}

public struct RefreshSchedule {
    public private(set) var failures = 0
    public private(set) var nextAttempt = Date.distantPast
    public private(set) var rateLimitedUntil = Date.distantPast
    public init() {}

    public func canRefresh(force: Bool, at now: Date = Date()) -> Bool {
        now >= rateLimitedUntil && (force || now >= nextAttempt)
    }
    public mutating func succeeded() { self = RefreshSchedule() }
    @discardableResult
    public mutating func failed(retryAfter: TimeInterval? = nil, at now: Date = Date()) -> TimeInterval {
        failures += 1
        let backoff = min(300, 30 * pow(2, Double(min(failures - 1, 4))))
        let delay = max(backoff, retryAfter ?? 0)
        nextAttempt = now.addingTimeInterval(delay)
        if retryAfter != nil { rateLimitedUntil = nextAttempt }
        return delay
    }
}
