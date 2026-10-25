// Local credential formats reference nanvon/cc-bar (MIT).
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import Foundation
import Security
import LocalAuthentication
import SQLite3
import CommonCrypto
import QuotaCore

struct KeychainAccessDeclined: LocalizedError {
    let service: String
    var errorDescription: String? { "已取消 \(service) 钥匙串访问。需要时点击刷新重试。" }
}

enum LocalCredentials {
    static func claudeToken() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        let file = directory.appendingPathComponent(".credentials.json")
        let data: Data
        if FileManager.default.fileExists(atPath: file.path) {
            guard let contents = try? Data(contentsOf: file) else { throw MonitorError.message("无法读取 Claude Code 登录态，请检查文件权限。") }
            data = contents
        } else {
            data = try keychain(service: "Claude Code-credentials", title: "Claude Code")
        }
        guard let root = try? ServiceQuotaParser.object(data),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = ServiceQuotaParser.nonEmpty(oauth["accessToken"] ?? oauth["access_token"]) else {
            throw MonitorError.message("未找到 Claude Code 订阅登录态，请先在 Claude Code 中登录。")
        }
        if let expiry = ServiceQuotaParser.date(oauth["expiresAt"]), expiry <= Date() {
            throw MonitorError.message("Claude Code 登录已过期，请打开 Claude Code 刷新登录后重试。")
        }
        return token
    }

    struct CursorSession { let subject: String; let cookie: String }

    static func cursorSession() throws -> CursorSession {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MonitorError.message("未找到 Cursor 登录态，请安装 Cursor 并登录。")
        }
        let stored = try sqliteValue(at: url, key: "cursorAuth/accessToken")
        let token = stored.hasPrefix("cursor-safe-storage:") ? try unsealCursor(stored) : stored
        let payload = jwtPayload(token)
        guard let subject = ServiceQuotaParser.nonEmpty(payload?["sub"]),
              let user = subject.split(separator: "|").last.map(String.init),
              user.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains),
              let expiry = ServiceQuotaParser.number(payload?["exp"]) else {
            throw MonitorError.message("Cursor 登录态格式不受支持，请更新客户端并重新登录。")
        }
        guard expiry > Date().timeIntervalSince1970 + 60 else {
            throw MonitorError.message("Cursor 登录已过期，请打开 Cursor 刷新登录后重试。")
        }
        return CursorSession(subject: subject, cookie: "WorkosCursorSessionToken=\(user)%3A%3A\(token)")
    }

    private static func keychain(service: String, title: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = "读取 \(title) 已有登录态以查询额度"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecUserCanceled || status == errSecAuthFailed { throw KeychainAccessDeclined(service: title) }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MonitorError.message("无法读取 \(title) 钥匙串登录态，请先登录并允许访问（\(status)）。")
        }
        return data
    }

    private static func sqliteValue(at url: URL, key: String) throws -> String {
        var database: OpaquePointer?
        // 无 WAL 时 immutable 避免 SQLite 在其他应用目录创建 sidecar；有 WAL 则读取最新提交。
        let hasWAL = FileManager.default.fileExists(atPath: url.path + "-wal")
        let filename = hasWAL ? url.path : url.absoluteString + "?immutable=1"
        let status = sqlite3_open_v2(filename, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        defer { if let database { sqlite3_close(database) } }
        guard status == SQLITE_OK else { throw MonitorError.message("无法只读打开 Cursor 登录数据库。") }
        sqlite3_busy_timeout(database, 250)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            throw MonitorError.message("Cursor 登录数据库格式不受支持。")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw MonitorError.message("Cursor 尚未登录，请先在 Cursor 中登录。")
        }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        let encoding: String.Encoding = data.contains(0) ? .utf16LittleEndian : .utf8
        guard let value = String(data: data, encoding: encoding)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw MonitorError.message("Cursor 登录态为空或无法解码。")
        }
        return value
    }

    private static func jwtPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let data = Data(base64Encoded: text) else { return nil }
        return try? ServiceQuotaParser.object(data)
    }

    private static func unsealCursor(_ value: String) throws -> String {
        let prefix = "cursor-safe-storage:v1:"
        guard value.hasPrefix(prefix), let blob = Data(base64Encoded: String(value.dropFirst(prefix.count))),
              blob.count > 3, blob.prefix(3) == Data("v10".utf8) else {
            throw MonitorError.message("Cursor 加密登录态版本不受支持。")
        }
        let password = try keychain(service: "Cursor Safe Storage", title: "Cursor")
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let derived = password.withUnsafeBytes { buffer in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), buffer.bindMemory(to: Int8.self).baseAddress,
                                password.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                                1003, &key, key.count)
        }
        guard derived == kCCSuccess else { throw MonitorError.message("无法解密 Cursor 登录态。") }
        let ciphertext = Data(blob.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var count = 0
        let status = ciphertext.withUnsafeBytes { bytes in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                    key, key.count, iv, bytes.baseAddress, ciphertext.count, &output, output.count, &count)
        }
        guard status == kCCSuccess, let token = String(bytes: output.prefix(count), encoding: .utf8), jwtPayload(token) != nil else {
            throw MonitorError.message("无法解密 Cursor 登录态，请在 Cursor 中重新登录。")
        }
        return token
    }
}
