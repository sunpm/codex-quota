import Foundation
import CryptoKit
import QuotaCore

enum MonitorError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let value): return value }
    }
}

struct AccountResponse: Decodable {
    struct Account: Decodable { let type: String; let email: String? }
    let account: Account?
}

struct QuotaSample {
    let fingerprint: String
    let windows: [QuotaWindow]
}

@MainActor
final class CodexClient {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private(set) var executablePath = ""

    static func locateExecutable() throws -> String {
        var candidates: [String] = []
        if let override = ProcessInfo.processInfo.environment["CODEX_QUOTA_CLI"] { candidates.append(override) }
        candidates += [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        ]
        let directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        candidates += directories.map { $0 + "/codex" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw MonitorError.message("未找到 Codex CLI。请先安装并登录 Codex，再点击刷新。")
        }
        return path
    }

    func sample() async throws -> QuotaSample {
        if process?.isRunning != true { try await connect() }
        let accountData = try await request("account/read", params: ["refreshToken": false])
        let account = try JSONDecoder().decode(AccountResponse.self, from: accountData)
        guard let user = account.account, user.type == "chatgpt" else {
            throw MonitorError.message("未检测到 ChatGPT 登录。请在 Codex 中登录后重试。")
        }
        let data = try await request("account/rateLimits/read")
        let response = try JSONDecoder().decode(LimitsResponse.self, from: data)
        let windows = response.windows()
        guard !windows.isEmpty else { throw MonitorError.message("当前账号没有返回可用的百分比额度。") }
        guard let identity = response.accountId ?? user.email, !identity.isEmpty else {
            throw MonitorError.message("无法识别当前账号，暂时不能安全比较额度变化。")
        }
        let fingerprint = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return QuotaSample(fingerprint: fingerprint, windows: windows)
    }

    private func connect() async throws {
        stop()
        executablePath = try Self.locateExecutable()
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = URL(fileURLWithPath: executablePath)
        child.arguments = ["app-server", "--listen", "stdio://"]
        // 由 Codex 自己读取和管理现有登录；应用不读取、复制或输出 token。
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        child.currentDirectoryURL = FileManager.default.temporaryDirectory
        process = child
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak child] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, let child, self.process === child else { return }
                if data.isEmpty { self.stop(reason: "Codex 连接已断开，将在下次刷新时重连。") }
                else { self.receive(data) }
            }
        }
        child.terminationHandler = { [weak self, weak child] _ in
            Task { @MainActor in
                guard let self, let child, self.process === child else { return }
                self.stop(reason: "Codex 进程已退出，将在下次刷新时重连。")
            }
        }
        do {
            try child.run()
            _ = try await request("initialize", params: ["clientInfo": ["name": "codex_quota_dock", "title": "Codex Quota Dock", "version": "0.2.0"]])
            try send(["method": "initialized", "params": [:]])
        } catch {
            stop()
            throw error
        }
    }

    private func request(_ method: String, params: [String: Any] = [:]) async throws -> Data {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                self?.stop(reason: "读取额度超时，将自动重试。")
            }
            do { try send(["id": id, "method": method, "params": params]) }
            catch { complete(id, result: .failure(error)) }
        }
    }

    private func send(_ object: [String: Any]) throws {
        guard let input, process?.isRunning == true else { throw MonitorError.message("Codex 尚未连接。") }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = message["id"] as? Int else { continue }
            if let error = message["error"] as? [String: Any] {
                let code = error["code"] as? Int ?? 0
                // 不展示服务端原始内容，避免错误响应包含账号或认证信息。
                complete(id, result: .failure(MonitorError.message("Codex 额度请求失败（\(code)），请确认登录和网络状态。")))
            } else if let result = message["result"], let data = try? JSONSerialization.data(withJSONObject: result) {
                complete(id, result: .success(data))
            }
        }
    }

    private func complete(_ id: Int, result: Result<Data, Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    func stop(reason: String = "连接已关闭。") {
        let child = process
        process = nil
        output?.readabilityHandler = nil
        child?.terminationHandler = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        buffer.removeAll()
        for id in Array(pending.keys) { complete(id, result: .failure(MonitorError.message(reason))) }
        if child?.isRunning == true { child?.terminate() }
    }
}
