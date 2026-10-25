// Local endpoint discovery and response shapes reference steipete/CodexBar (MIT).
// Copyright (c) 2026 Peter Steinberger. See Resources/ThirdPartyNotices/CodexBar-LICENSE.txt.
import Foundation
import QuotaCore

@MainActor
final class AntigravityClient: QuotaClient {
    private let http = QuotaHTTP(local: true)
    private struct Endpoint { let scheme: String; let port: Int; let token: String }
    private struct Server { let pid: String; let token: String; let extensionPort: Int?; let extensionToken: String? }

    func sample() async throws -> QuotaSample {
        let servers = try await Task.detached(priority: .utility) { try Self.servers() }.value
        guard !servers.isEmpty else { throw MonitorError.message("请启动 Antigravity 并登录，等待本地语言服务就绪。") }
        var lastError: Error = MonitorError.message("未找到可读取的 Antigravity 本地额度服务。")
        for server in servers {
            let ports = try await Task.detached(priority: .utility) { try Self.ports(pid: server.pid) }.value
            var endpoints = ports.map { Endpoint(scheme: "https", port: $0, token: server.token) }
            if let port = server.extensionPort {
                endpoints.append(Endpoint(scheme: "http", port: port, token: server.extensionToken ?? server.token))
            }
            for endpoint in endpoints {
                try Task.checkCancellation()
                do {
                    let status = try await request("GetUserStatus", endpoint: endpoint, body: [
                        "metadata": ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "en"]
                    ])
                    guard let identity = try ServiceQuotaParser.antigravityAccount(status) else {
                        throw MonitorError.message("Antigravity 未返回账号身份，请确认已登录。")
                    }
                    var windows = try ServiceQuotaParser.antigravityStatus(status)
                    do {
                        let data = try await request("RetrieveUserQuotaSummary", endpoint: endpoint, body: ["forceRefresh": true])
                        let grouped = try ServiceQuotaParser.antigravitySummary(data)
                        if !grouped.isEmpty { windows = grouped }
                    } catch let error as QuotaHTTPError where [401, 403, 429].contains(error.status) {
                        throw error
                    } catch {
                        // 旧版 IDE 没有分组接口，仍使用同一响应账号的模型额度。
                        if windows.isEmpty { throw error }
                    }
                    guard !windows.isEmpty else { throw MonitorError.message("Antigravity 未返回可用的模型额度。") }
                    return QuotaSample(fingerprint: accountFingerprint(identity), windows: windows)
                } catch let error as QuotaHTTPError where error.status == 429 {
                    throw error
                } catch { lastError = error }
            }
        }
        throw lastError
    }

    private func request(_ method: String, endpoint: Endpoint, body: [String: Any]) async throws -> Data {
        let url = URL(string: "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)/exa.language_server_pb.LanguageServerService/\(method)")!
        return try await http.data(url: url, headers: ["X-Codeium-Csrf-Token": endpoint.token, "Connect-Protocol-Version": "1"], body: body, timeout: 3)
    }

    nonisolated private static func servers() throws -> [Server] {
        let output = try command("/bin/ps", ["-U", String(getuid()), "-o", "pid=,command="])
        return output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2, Int(parts[0]) != nil else { return nil }
            let command = String(parts[1]), lower = command.lowercased()
            guard lower.contains("antigravity"), lower.contains("language_server") || lower.contains("language-server"),
                  let token = flag("csrf_token", in: command) else { return nil }
            return Server(pid: String(parts[0]), token: token,
                          extensionPort: flag("extension_server_port", in: command).flatMap(Int.init).flatMap { (1...65535).contains($0) ? $0 : nil },
                          extensionToken: flag("extension_server_csrf_token", in: command))
        }
    }

    nonisolated private static func flag(_ name: String, in command: String) -> String? {
        let expression = try? NSRegularExpression(pattern: "--\(name)(?:=|\\s+)([^\\s]+)")
        guard let match = expression?.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let range = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    nonisolated private static func ports(pid: String) throws -> [Int] {
        let output = try command("/usr/sbin/lsof", ["-nP", "-a", "-p", pid, "-iTCP", "-sTCP:LISTEN", "-Fn"])
        return Array(Set(output.split(separator: "\n").compactMap { line -> Int? in
            guard line.hasPrefix("n"), let suffix = line.split(separator: ":").last,
                  let port = Int(suffix), (1...65535).contains(port) else { return nil }
            return port
        })).sorted()
    }

    nonisolated private static func command(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        output.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    func stop() { http.stop() }
}
