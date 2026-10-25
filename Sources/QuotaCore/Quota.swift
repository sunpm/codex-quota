import Foundation

public struct LimitsResponse: Decodable {
    public let accountId: String?
    public let rateLimits: LimitBucket?
    public let rateLimitsByLimitId: [String: LimitBucket]?

    public func windows() -> [QuotaWindow] {
        let buckets: [String: LimitBucket]
        if let all = rateLimitsByLimitId, !all.isEmpty {
            buckets = all
        } else if let legacy = rateLimits {
            buckets = [legacy.limitId ?? "codex": legacy]
        } else {
            buckets = [:]
        }
        return buckets.sorted { $0.key < $1.key }.flatMap { key, bucket in
            [("primary", bucket.primary), ("secondary", bucket.secondary)].compactMap { slot, value in
                guard let value, let used = value.usedPercent, used.isFinite, (0...100).contains(used) else { return nil }
                return QuotaWindow(
                    id: "\(key):\(slot):\(value.windowDurationMins ?? 0)",
                    bucket: key, name: bucket.limitName ?? key,
                    usedPercent: used, durationMinutes: value.windowDurationMins,
                    resetsAt: value.resetsAt.map { Date(timeIntervalSince1970: $0) }
                )
            }
        }
    }
}

public struct LimitBucket: Decodable {
    public let limitId: String?
    public let limitName: String?
    public let primary: LimitWindow?
    public let secondary: LimitWindow?
}

public struct LimitWindow: Decodable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?
}

public struct QuotaWindow: Identifiable, Codable, Equatable {
    public let id: String
    public let bucket: String
    public let name: String
    public let usedPercent: Double
    public let durationMinutes: Int?
    public let resetsAt: Date?

    public init(id: String, bucket: String = "codex", name: String = "Codex", usedPercent: Double, durationMinutes: Int? = nil, resetsAt: Date? = nil) {
        self.id = id
        self.bucket = bucket
        self.name = name
        self.usedPercent = usedPercent
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }

    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    // 不把 99.9% 四舍五入成 100%，让显示和通知的含义一致。
    public var percentageText: String { "\(Int(remaining.rounded(.down)))%" }
    public var periodText: String {
        guard let minutes = durationMinutes, minutes > 0 else { return "额度" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
}

public struct RecoveryState: Codable, Equatable {
    public var accountFingerprint: String
    public var usedByWindow: [String: Double]

    public init(accountFingerprint: String, usedByWindow: [String: Double]) {
        self.accountFingerprint = accountFingerprint
        self.usedByWindow = usedByWindow
    }
}

public struct RecoveryTracker {
    public private(set) var state: RecoveryState?
    public init(state: RecoveryState? = nil) { self.state = state }

    public mutating func observe(account: String, windows: [QuotaWindow]) -> [QuotaWindow] {
        let previous = state?.accountFingerprint == account ? state?.usedByWindow ?? [:] : [:]
        let recovered = windows.filter { window in
            guard let oldUsed = previous[window.id] else { return false }
            return oldUsed > 0 && window.usedPercent == 0
        }
        state = RecoveryState(accountFingerprint: account, usedByWindow: Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.usedPercent) }))
        return recovered
    }
}
