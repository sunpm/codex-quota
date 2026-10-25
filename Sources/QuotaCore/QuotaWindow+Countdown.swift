import Foundation

extension QuotaWindow {
    /// 菜单栏紧凑格式：04:25:54 或 6d 13:25:36。
    public func compactResetCountdown(at now: Date = Date()) -> String {
        guard let resetsAt else { return "--:--:--" }
        guard resetsAt > now else { return "等待重置" }
        let total = Int(ceil(resetsAt.timeIntervalSince(now)))
        let days = total / 86400
        let hours = total / 3600 % 24
        let minutes = total / 60 % 60
        let seconds = total % 60
        let clock = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        return days > 0 ? "\(days)d \(clock)" : clock
    }
}
