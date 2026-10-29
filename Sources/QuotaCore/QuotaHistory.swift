import Foundation

/// 仅保留最近使用账号的额度观测；账号用摘要识别，不保存登录信息。
public struct QuotaHistory: Codable {
    public struct Point: Codable, Identifiable {
        public let date: Date
        public let usedPercent: Double
        public let segment: Int
        public var id: Date { date }
    }

    public struct Series: Codable {
        public let window: QuotaWindow
        public var points: [Point]
    }

    public private(set) var accountFingerprint: String?
    public private(set) var series: [String: Series] = [:]
    private var lastObservation: Date?

    public init() {}

    public mutating func observe(account: String, windows: [QuotaWindow], at date: Date,
                                 continuous: Bool, maximumGap: TimeInterval) {
        if accountFingerprint != account {
            series = [:]
            lastObservation = nil
            accountFingerprint = account
        }
        let cutoff = date.addingTimeInterval(-7 * 24 * 60 * 60)
        series = series.compactMapValues { value in
            let points = value.points.filter { $0.date >= cutoff }
            return points.isEmpty ? nil : Series(window: value.window, points: points)
        }
        for window in windows {
            let previous = series[window.id]
            var points = previous?.points ?? []
            let last = points.last
            let connects = last.map {
                continuous && $0.date == lastObservation
                    && date.timeIntervalSince($0.date) > 0 && date.timeIntervalSince($0.date) <= maximumGap
                    && previous?.window.resetsAt == window.resetsAt && window.usedPercent >= $0.usedPercent
            } ?? false
            let segment = (last?.segment ?? 0) + (connects ? 0 : 1)
            let point = Point(date: date, usedPercent: window.usedPercent, segment: segment)
            // 每五分钟保留最新实测值，同时保留每段起点；重置与中断不能被合并。
            if connects, let last, points.count > 1, points[points.count - 2].segment == segment,
               Int(last.date.timeIntervalSince1970 / 300) == Int(date.timeIntervalSince1970 / 300) {
                points[points.count - 1] = point
            } else {
                points.append(point)
            }
            series[window.id] = Series(window: window, points: points)
        }
        lastObservation = date
    }
}
