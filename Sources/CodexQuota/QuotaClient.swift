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
        case 401, 403: return "登录已失效或无读取权限，请在 Codex 中重新登录。"
        case 429: return "服务请求过于频繁，等待限流冷却。"
        default: return "额度接口请求失败（HTTP \(status)）。"
        }
    }
}
