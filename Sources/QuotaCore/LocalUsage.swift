// Log formats and deduplication adapted from nanvon/cc-bar (MIT).
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import Foundation
import CoreFoundation

public struct UsageTokens: Equatable, Sendable {
    public var input: Int = 0
    public var output: Int = 0
    public var cached: Int = 0
    public var cacheWrite: Int = 0
    /// 长保留期缓存写入是 cacheWrite 的子集，不再次加到总量。
    public var cacheWriteLong: Int = 0
    public var total: Int { input + output + cached + cacheWrite }
    public var cacheHitRate: Double? {
        let incoming = input + cached + cacheWrite
        return incoming > 0 ? Double(cached) / Double(incoming) : nil
    }
    public init() {}
    public mutating func add(_ other: Self) {
        input += other.input; output += other.output
        cached += other.cached; cacheWrite += other.cacheWrite
        cacheWriteLong += other.cacheWriteLong
    }
}

public struct UsageRecord: Identifiable, Sendable {
    public let id: String
    public let service: QuotaService
    public let session: String
    public let project: String
    public let model: String
    public let date: Date
    public let tokens: UsageTokens
    public let serviceTier: String
    public let isUSOnly: Bool
}

public struct UsageScan: Sendable {
    public var records: [UsageRecord] = []
    public var warnings: [String] = []
    public var fileCount = 0
    public init() {}
}

/// 只缓存文件元数据和用量字段，不保存消息正文或登录信息。
public actor LocalUsageReader {
    private struct CachedFile {
        let size: Int
        let modified: Date
        let records: [UsageRecord]
        let invalidLines: Int
    }
    private var cache: [URL: CachedFile] = [:]
    public init() {}

    public func scan() -> UsageScan {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        let codex = env["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        let claude = env["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        let roots: [(QuotaService, URL)] = [
            (.codex, codex.appendingPathComponent("sessions")),
            (.codex, codex.appendingPathComponent("archived_sessions")),
            (.claude, claude.appendingPathComponent("projects"))
        ]
        var result = UsageScan()
        var files: [(QuotaService, URL)] = []
        var compressed = 0
        var failures = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for (service, root) in roots {
            guard manager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles], errorHandler: { _, _ in failures += 1; return true }) else {
                failures += 1; continue
            }
            for case let file as URL in enumerator {
                if file.pathExtension == "jsonl" { files.append((service, file)) }
                else if file.lastPathComponent.hasSuffix(".jsonl.zst") { compressed += 1 }
            }
        }
        // 父会话先入账，避免 fork 重放后的时间戳把旧用量挪到新日期。
        files.sort { $0.1.lastPathComponent < $1.1.lastPathComponent }
        var records: [String: UsageRecord] = [:]
        var invalid = 0
        var alive: Set<URL> = []
        for (service, file) in files {
            alive.insert(file)
            do {
                let values = try file.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true else { continue }
                let size = values.fileSize ?? 0
                let modified = values.contentModificationDate ?? .distantPast
                let parsed: CachedFile
                if let saved = cache[file], saved.size == size, saved.modified == modified {
                    parsed = saved
                } else {
                    parsed = try parse(file, service: service, size: size, modified: modified)
                    cache[file] = parsed
                }
                invalid += parsed.invalidLines
                result.fileCount += 1
                for record in parsed.records {
                    // Claude 的同一消息可能有多个流式快照，保留完整用量最大的一个。
                    if let old = records[record.id] {
                        if service == .claude && record.tokens.total > old.tokens.total { records[record.id] = record }
                    } else { records[record.id] = record }
                }
            } catch {
                failures += 1
                // 短暂读取失败保留上一次已解析的文件结果，并在界面标记不完整。
                for record in cache[file]?.records ?? [] where records[record.id] == nil { records[record.id] = record }
            }
        }
        cache = cache.filter { alive.contains($0.key) }
        result.records = records.values.sorted { $0.date < $1.date }
        if failures > 0 { result.warnings.append("\(failures) 处日志无法读取，统计可能不完整") }
        if invalid > 0 { result.warnings.append("\(invalid) 条记录格式无效，已跳过") }
        if compressed > 0 { result.warnings.append("\(compressed) 个压缩日志暂未计入") }
        return result
    }

    private func parse(_ file: URL, service: QuotaService, size: Int, modified: Date) throws -> CachedFile {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        var records: [UsageRecord] = []
        var invalid = 0
        let filename = file.deletingPathExtension().lastPathComponent
        let filenameID = String(filename.suffix(36))
        var session = UUID(uuidString: filenameID) == nil ? filename : filenameID
        var emitter = session
        var project = ""
        var model = "未知模型"
        var sawMeta = false
        var serviceTier = "standard"
        var isUSOnly = false
        var previousSignature: String?
        var lineNumber = 0

        func consume(_ line: Data) {
            lineNumber += 1
            guard !line.isEmpty else { return }
            guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { invalid += 1; return }
            let type = row["type"] as? String
            let payload = row["payload"] as? [String: Any] ?? [:]
            if service == .codex {
                if type == "session_meta" {
                    emitter = payload["id"] as? String ?? payload["session_id"] as? String ?? emitter
                    if !sawMeta {
                        project = payload["cwd"] as? String ?? ""
                        if UUID(uuidString: filenameID) == nil { session = emitter }
                        sawMeta = true
                    }
                    return
                }
                if type == "turn_context" {
                    model = payload["model"] as? String ?? model
                    if let tier = payload["service_tier"] as? String { serviceTier = tier }
                    return
                }
                if type == "event_msg", payload["type"] as? String == "thread_settings_applied" {
                    let settings = payload["thread_settings"] as? [String: Any] ?? payload
                    model = settings["model"] as? String ?? model
                    serviceTier = settings["service_tier"] as? String ?? "unknown"
                    return
                }
                guard type == "event_msg", payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let usage = info["last_token_usage"] as? [String: Any] else { return }
                let total = info["total_token_usage"] as? [String: Any]
                let signature = total.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                    .map { String(decoding: $0, as: UTF8.self) }
                if let signature, signature == previousSignature { return }
                previousSignature = signature
                guard let tokens = tokenCounts(usage, codex: true) else { invalid += 1; return }
                guard tokens.total > 0 else { return }
                append(row, tokens: tokens, id: "codex:\(emitter):\(signature ?? "\(session):\(lineNumber)")")
            } else {
                guard type == "assistant", let message = row["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let messageID = message["id"] as? String,
                      let tokens = tokenCounts(usage, codex: false), tokens.total > 0 else { return }
                session = row["sessionId"] as? String ?? session
                project = row["cwd"] as? String ?? project
                model = message["model"] as? String ?? "未知模型"
                serviceTier = usage["speed"] as? String ?? "standard"
                isUSOnly = usage["inference_geo"] as? String == "us"
                guard model != "<synthetic>" else { return }
                append(row, tokens: tokens, id: "claude:\(messageID):\(row["requestId"] as? String ?? "")")
            }
        }
        func append(_ row: [String: Any], tokens: UsageTokens, id: String) {
            guard let stamp = row["timestamp"] as? String,
                  let date = fractional.date(from: stamp) ?? whole.date(from: stamp) else { invalid += 1; return }
            records.append(UsageRecord(id: id, service: service, session: session, project: project,
                                       model: model, date: date, tokens: tokens,
                                       serviceTier: serviceTier.lowercased(), isUSOnly: isUSOnly))
        }

        // ponytail: 变更文件从头解析；若单个日志增长到影响刷新，再改为 byte-offset 增量读取。
        var pending = Data()
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            pending.append(chunk)
            var start = pending.startIndex
            while let end = pending[start...].firstIndex(of: 10) {
                consume(pending.subdata(in: start..<end))
                start = end + 1
            }
            if start > pending.startIndex { pending = Data(pending[start...]) }
        }
        // 正在写入的末行留到下次刷新；完整但没有换行符的 JSON 仍可读取。
        if !pending.isEmpty, (try? JSONSerialization.jsonObject(with: pending)) != nil { consume(pending) }
        return CachedFile(size: size, modified: modified, records: records, invalidLines: invalid)
    }

    private func tokenCounts(_ values: [String: Any], codex: Bool) -> UsageTokens? {
        func count(_ key: String) -> Int? {
            guard let value = values[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            let number = value.doubleValue
            guard number.isFinite, number >= 0, number < Double(Int.max / 16), number.rounded(.down) == number else { return nil }
            return value.intValue
        }
        guard let input = count("input_tokens"), let output = count("output_tokens") else { return nil }
        var tokens = UsageTokens()
        tokens.output = output
        if codex {
            tokens.cached = count("cached_input_tokens") ?? count("cache_read_input_tokens") ?? 0
            tokens.cacheWrite = count("cache_write_input_tokens") ?? count("cache_write_tokens") ?? 0
            guard tokens.cached + tokens.cacheWrite <= input else { return nil }
            tokens.input = input - tokens.cached - tokens.cacheWrite
            // Codex 聚合计数未提供缓存保留期，按短保留期作 API 参考估算。
        } else {
            tokens.input = input
            tokens.cached = count("cache_read_input_tokens") ?? 0
            let detail = values["cache_creation"] as? [String: Any] ?? [:]
            tokens.cacheWrite = count("cache_creation_input_tokens")
                ?? max(0, (detail["ephemeral_5m_input_tokens"] as? Int ?? 0) + (detail["ephemeral_1h_input_tokens"] as? Int ?? 0))
            tokens.cacheWriteLong = min(tokens.cacheWrite, max(0, detail["ephemeral_1h_input_tokens"] as? Int ?? 0))
        }
        return tokens
    }
}
