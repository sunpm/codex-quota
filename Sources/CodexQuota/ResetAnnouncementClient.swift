import Foundation
import QuotaCore

@MainActor
final class ResetAnnouncementClient {
    enum Response {
        case updated(ResetAnnouncementFeed, etag: String?)
        case notModified
    }

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration)
    }

    func fetch(etag: String?) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://aihot.news/api/v1/codex-resets/recent")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexQuota", forHTTPHeaderField: "User-Agent")
        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        let (data, rawResponse) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = rawResponse as? HTTPURLResponse else {
            throw MonitorError.message("AIHOT 未返回有效响应。")
        }
        if response.statusCode == 304 { return .notModified }
        guard response.statusCode == 200 else {
            var retryAfter: TimeInterval?
            if response.statusCode == 429 || response.statusCode == 503 {
                let raw = response.value(forHTTPHeaderField: "Retry-After") ?? ""
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                let delay = Double(raw) ?? formatter.date(from: raw)?.timeIntervalSinceNow ?? 600
                retryAfter = delay.isFinite ? max(600, delay) : 600
            }
            throw QuotaHTTPError(status: response.statusCode, retryAfter: retryAfter)
        }
        return .updated(try ResetAnnouncementFeed.decode(data), etag: response.value(forHTTPHeaderField: "ETag"))
    }

    func stop() { session.invalidateAndCancel() }
}
