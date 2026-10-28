import Foundation

/// AIHOT 的公开公告，与个人账号的 QuotaWindow、RecoveryTracker 无关。
public struct ResetAnnouncementFeed: Codable {
    public let schemaVersion: Int
    public let checkedAt: Date?
    public let events: [ResetAnnouncement]
    public let monitor: Monitor?

    public struct Monitor: Codable {
        public let status: String
        public let lastCollectedAt: Date?
        public let lastVerifiedAt: Date?
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let whole = ISO8601DateFormatter()
            guard let date = fractional.date(from: value) ?? whole.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid announcement date")
            }
            return date
        }
        let feed = try decoder.decode(Self.self, from: data)
        // 只在外部响应边界验证版本、标识与可打开的原帖地址。
        guard feed.schemaVersion == 1,
              Set(feed.events.map(\.id)).count == feed.events.count,
              feed.events.allSatisfy({ event in
                  !event.id.isEmpty && event.posts.allSatisfy { $0.url == ResetAnnouncementPost.sourceURL(for: $0.id) }
              }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported announcement feed"))
        }
        return feed
    }

    public var sourceUpdatedAt: Date? { monitor?.lastVerifiedAt ?? checkedAt }

    public func sourceStatus(at now: Date) -> String? {
        if monitor?.status == "attention" { return "AIHOT 数据待核实" }
        if monitor?.status == "delayed" { return "AIHOT 更新延迟" }
        guard let date = sourceUpdatedAt else { return "来源更新时间未知" }
        if now.timeIntervalSince(date) > 30 * 60 { return "AIHOT 数据已过期" }
        if let monitor, monitor.status != "healthy" { return "AIHOT 监测状态未知" }
        return nil
    }
}

public struct ResetAnnouncement: Codable, Identifiable {
    public enum Kind: String, Codable { case directReset = "direct_reset", resetCredit = "reset_credit" }
    public enum Phase: String, Codable { case announced, confirmed }
    public enum DisplayStatus: String, Codable {
        case announced, confirmed
        case inProgress = "in_progress", expiredUnconfirmed = "expired_unconfirmed", likelyCompleted = "likely_completed"
    }
    public struct Presentation: Codable {
        public let status: DisplayStatus
        public let scopeLabel: String?
    }
    public struct Window: Codable {
        public let through: Date
        public let label: String
    }

    public let id: String
    public let type: Kind
    public let displayLabel: String?
    public let status: Phase
    public let presentation: Presentation?
    public let confirmedAt: Date?
    public let confirmationBasis: String?
    public let schedule: Window?
    public let estimate: Window?
    public let updatedAt: Date
    public let posts: [ResetAnnouncementPost]

    public var label: String { displayLabel ?? "重置动态" }
    public var latestPost: ResetAnnouncementPost? { posts.max { $0.publishedAt < $1.publishedAt } }

    public func displayStatus(at now: Date) -> DisplayStatus {
        if status == .confirmed { return .confirmed }
        let display = presentation?.status ?? .announced
        // 时间流逝只改变“待确认”显示，不能产生确认事件。
        if display == .announced || display == .inProgress,
           let deadline = estimate?.through ?? schedule?.through, now > deadline {
            return .expiredUnconfirmed
        }
        return display == .confirmed ? .announced : display
    }

    public func statusText(at now: Date) -> String {
        switch displayStatus(at: now) {
        case .announced: return "已预告"
        case .inProgress: return "正在生效"
        case .confirmed:
            if confirmationBasis == "source_post" { return "Tibo 已确认" }
            if confirmationBasis == "receipt_review" { return "AIHOT 到账核实" }
            return "公告已确认"
        case .expiredUnconfirmed, .likelyCompleted: return "已过预计时间，未确认"
        }
    }

    public var notificationTitle: String {
        let action = type == .resetCredit ? "发放重置卡" : "重置"
        if status == .announced { return "Tibo 预告\(action)" }
        return confirmationBasis == "source_post" ? "Tibo 已确认\(action)" : "AIHOT 已核实\(action)公告"
    }
}

public struct ResetAnnouncementPost: Codable, Identifiable {
    public let id: String
    public let publishedAt: Date
    public let text: String
    public let url: URL

    public static func sourceURL(for id: String) -> URL? {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return URL(string: "https://x.com/thsottiaux/status/\(id)")
    }
}

public struct ResetAnnouncementTracker: Codable {
    public var hasBaseline = false
    private var seen: [String: Date] = [:]
    public init() {}

    public mutating func observe(_ events: [ResetAnnouncement], notify: Bool, at now: Date = Date()) -> [ResetAnnouncement] {
        seen = seen.filter { now.timeIntervalSince($0.value) < 30 * 24 * 60 * 60 }
        var notifications: [ResetAnnouncement] = []
        for event in events.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            let keys = event.posts.map { "\($0.id):\(event.status.rawValue)" }
            let previouslySeen = keys.contains { seen[$0] != nil }
            let display = event.displayStatus(at: now)
            if hasBaseline, notify, !previouslySeen, let post = event.latestPost,
               now.timeIntervalSince(post.publishedAt) >= 0,
               now.timeIntervalSince(post.publishedAt) <= 24 * 60 * 60,
               display != .expiredUnconfirmed, display != .likelyCompleted {
                notifications.append(event)
            }
            for key in keys { seen[key] = now }
            // 上游重新归组或回退阶段时，不补发已确认事件的旧预告。
            if event.status == .confirmed {
                for post in event.posts { seen["\(post.id):announced"] = now }
            }
        }
        hasBaseline = true
        return notifications
    }
}
