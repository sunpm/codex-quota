import Foundation
import CryptoKit
import QuotaCore

@MainActor
protocol QuotaClient: AnyObject {
    func sample() async throws -> QuotaSample
    func stop()
}

func accountFingerprint(_ identity: String) -> String {
    SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
}

struct QuotaHTTPError: LocalizedError {
    let status: Int
    let retryAfter: TimeInterval?
    var errorDescription: String? {
        switch status {
        case 401, 403: return "登录已失效或无读取权限，请在对应服务中重新登录。"
        case 429: return "服务请求过于频繁，等待限流冷却。"
        default: return "额度接口请求失败（HTTP \(status)）。"
        }
    }
}

/// 仅 Antigravity 的固定回环地址使用本地自签名证书；远端沿用系统验证。
private final class QuotaSessionDelegate: NSObject, URLSessionTaskDelegate {
    let local: Bool
    init(local: Bool) { self.local = local }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if local, challenge.protectionSpace.host == "127.0.0.1",
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // 登录跳转不是额度响应，避免将手动认证头传给其他地址。
        completionHandler(nil)
    }
}

@MainActor
final class QuotaHTTP {
    private let session: URLSession
    init(local: Bool = false) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration, delegate: QuotaSessionDelegate(local: local), delegateQueue: nil)
    }
    func data(url: URL, headers: [String: String] = [:], body: [String: Any]? = nil, timeout: TimeInterval = 20) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw MonitorError.message("无法连接额度服务，请检查网络或客户端运行状态。") }
        guard let response = response as? HTTPURLResponse else { throw MonitorError.message("服务未返回有效 HTTP 响应。") }
        guard (200..<300).contains(response.statusCode) else {
            var retryAfter: TimeInterval?
            if response.statusCode == 429 {
                let raw = response.value(forHTTPHeaderField: "Retry-After") ?? ""
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                let value = Double(raw) ?? formatter.date(from: raw)?.timeIntervalSinceNow ?? 300
                retryAfter = value.isFinite ? max(30, value) : 300
            }
            throw QuotaHTTPError(status: response.statusCode, retryAfter: retryAfter)
        }
        return data
    }
    func stop() { session.invalidateAndCancel() }
}

@MainActor
final class ClaudeClient: QuotaClient {
    private let http = QuotaHTTP()
    private var cachedIdentity: (tokenHash: String, fingerprint: String)?
    func sample() async throws -> QuotaSample {
        let token = try await Task.detached(priority: .utility) { try LocalCredentials.claudeToken() }.value
        let headers = ["Authorization": "Bearer \(token)", "anthropic-beta": "oauth-2025-04-20"]
        let tokenHash = accountFingerprint(token)
        let fingerprint: String
        if let cachedIdentity, cachedIdentity.tokenHash == tokenHash { fingerprint = cachedIdentity.fingerprint }
        else {
            let profile = try await http.data(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!, headers: headers)
            let root = try ServiceQuotaParser.object(profile)
            let account = root["account"] as? [String: Any] ?? [:]
            let organization = root["organization"] as? [String: Any] ?? [:]
            guard let identity = ServiceQuotaParser.nonEmpty(account["uuid"] ?? account["id"] ?? account["email"]) else {
                throw MonitorError.message("Claude 未返回可识别账号，无法比较额度变化。")
            }
            fingerprint = accountFingerprint(identity + ":" + (ServiceQuotaParser.nonEmpty(organization["uuid"]) ?? ""))
            cachedIdentity = (tokenHash, fingerprint)
        }
        let data = try await http.data(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, headers: headers)
        let windows = try ServiceQuotaParser.claude(data)
        guard !windows.isEmpty else { throw MonitorError.message("Claude 未返回可用额度，请确认已使用订阅账号登录 Claude Code。") }
        return QuotaSample(fingerprint: fingerprint, windows: windows)
    }
    func stop() { http.stop() }
}

@MainActor
final class CursorClient: QuotaClient {
    private let http = QuotaHTTP()
    func sample() async throws -> QuotaSample {
        let auth = try await Task.detached(priority: .utility) { try LocalCredentials.cursorSession() }.value
        let data = try await http.data(url: URL(string: "https://cursor.com/api/usage-summary")!, headers: ["Cookie": auth.cookie])
        let windows = try ServiceQuotaParser.cursor(data)
        guard !windows.isEmpty else { throw MonitorError.message("Cursor 未返回可用的有限额度；当前套餐或接口可能不支持百分比查询。") }
        return QuotaSample(fingerprint: accountFingerprint(auth.subject), windows: windows)
    }
    func stop() { http.stop() }
}
