// Log formats and deduplication adapted from nanvon/cc-bar (MIT).
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import Foundation
import CoreFoundation

public struct UsageTokens: Codable, Equatable, Sendable {
    public var input: Int = 0
    public var output: Int = 0
    public var cached: Int = 0
    public var cacheWrite: Int = 0
    /// 长保留期缓存写入是 cacheWrite 的子集，不再次加到总量。
    public var cacheWriteLong: Int = 0
    /// nil 为旧历史，false 为日志未提供；两者都不能把零显示为已确认的零。
    public var cacheWriteReported: Bool?
    public var reportedCacheWrite: Int? {
        cacheWriteReported == true || cacheWrite > 0 ? cacheWrite : nil
    }
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

public enum UsageSpeedTier: String, CaseIterable, Sendable {
    case standard = "Standard", fast = "Fast", ultrafast = "Ultrafast"
}

public struct UsageRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let service: QuotaService
    public internal(set) var session: String
    public let project: String
    public let model: String
    public let date: Date
    public internal(set) var tokens: UsageTokens
    public let serviceTier: String
    /// 保留旧版历史的序列化字段，Codex 采集不使用地区附加费。
    public let isUSOnly: Bool
    public internal(set) var serviceTierReported: Bool?
    /// 从日志事件边界估算的秒数，不是网络请求的实测计时。
    public internal(set) var estimatedDuration: TimeInterval?
    public internal(set) var estimatedFirstToken: TimeInterval?

    public var estimatedOutputTokensPerSecond: Double? {
        guard tokens.output >= 200, let estimatedDuration, estimatedDuration >= 1 else { return nil }
        return Double(tokens.output) / estimatedDuration
    }

    /// 明细分组与计费共用日志档位映射；未知档位不得按 Standard 计费。
    public var speedTier: UsageSpeedTier? {
        switch serviceTier {
        case "standard", "default", "auto": return .standard
        case "fast", "priority": return .fast
        case "ultrafast": return .ultrafast
        default: return nil
        }
    }
}

public struct UsageScan: Sendable {
    public var records: [UsageRecord] = []
    /// 原始工作目录到已确认主项目的映射；records 中的路径保持不变。
    public var projectRoots: [String: String] = [:]
    public var warnings: [String] = []
    public var historyError: String?
    public var fileCount = 0
    public init() {}

    public func projectPath(for directory: String) -> String { projectRoots[directory] ?? directory }
}

/// 文件元数据仅用于内存缓存，用量字段持久保存；不保存消息正文或登录信息。
public actor LocalUsageReader {
    private struct CachedFile {
        let size: Int
        let modified: Date
        let records: [UsageRecord]
        let invalidLines: Int
        let codexContinuation: (segment: String, thread: String)?
    }
    private var cache: [URL: CachedFile] = [:]
    private let historyStore: UsageHistoryStore
    private var history = UsageHistory()
    private var savedHistory = UsageHistory()
    private var historyLoaded = false

    public init(historyURL: URL? = nil) {
        historyStore = UsageHistoryStore(url: historyURL)
    }

    /// 只清除本应用的 Codex 历史；保留旧服务记录，现存日志在下一次扫描时重新采集。
    public func clearHistory() throws {
        try historyStore.clear()
        history = try historyStore.load()
        savedHistory = history
        historyLoaded = true
        cache.removeAll()
    }

    public func scan(rescan: Bool = false) -> UsageScan {
        if rescan { cache.removeAll() }
        var result = UsageScan()
        if !historyLoaded {
            do {
                history = try historyStore.load()
                savedHistory = history
                historyLoaded = true
            } catch {
                // 损坏或不支持的历史不能当成首装覆盖，仍允许查看现存日志。
                result.historyError = "已保存历史无法读取，原文件已保留；当前仅显示现存日志。"
            }
        }
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        let codex = env["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".codex")
        let roots = [codex.appendingPathComponent("sessions"), codex.appendingPathComponent("archived_sessions")]
        var files: [URL] = []
        var failures = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for root in roots {
            guard manager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles], errorHandler: { _, _ in failures += 1; return true }) else {
                failures += 1; continue
            }
            for case let file as URL in enumerator {
                if file.pathExtension == "jsonl" || file.lastPathComponent.hasSuffix(".jsonl.zst") {
                    files.append(file)
                }
            }
        }
        // 父会话先入账，避免 fork 重放后的时间戳把旧用量挪到新日期。
        files.sort {
            $0.lastPathComponent == $1.lastPathComponent ? $0.path < $1.path
                : $0.lastPathComponent < $1.lastPathComponent
        }
        var records = history.records.filter { $0.value.service == .codex }
        func merge(_ record: UsageRecord) {
            if let old = records[record.id] {
                // fork 重放不得把历史挪到更晚的时间。
                guard record.date <= old.date else { return }
                if record.date == old.date {
                    guard old.tokens.input == record.tokens.input, old.tokens.output == record.tokens.output,
                          old.tokens.cached == record.tokens.cached, old.tokens.cacheWrite == record.tokens.cacheWrite,
                          old.tokens.cacheWriteLong == record.tokens.cacheWriteLong else { return }
                    // 原日志重扫时补全计时和字段来源；不让 fork 或压缩副本抹掉已知值。
                    var enriched = old
                    enriched.estimatedDuration = old.estimatedDuration ?? record.estimatedDuration
                    enriched.estimatedFirstToken = old.estimatedFirstToken ?? record.estimatedFirstToken
                    enriched.serviceTierReported = old.serviceTierReported ?? record.serviceTierReported
                    enriched.tokens.cacheWriteReported = old.tokens.cacheWriteReported ?? record.tokens.cacheWriteReported
                    records[record.id] = enriched
                    return
                }
            }
            records[record.id] = record
        }
        var invalid = 0
        var codexThreads: [String: String] = [:]
        var alive: Set<URL> = []
        for file in files {
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
                    parsed = try parse(file, size: size, modified: modified)
                    cache[file] = parsed
                }
                invalid += parsed.invalidLines
                result.fileCount += 1
                if let continuation = parsed.codexContinuation {
                    codexThreads[continuation.segment] = continuation.thread
                }
                for record in parsed.records { merge(record) }
            } catch {
                failures += 1
                // 短暂读取失败保留上一次已解析的文件结果，并在界面标记不完整。
                if let saved = cache[file] {
                    if let continuation = saved.codexContinuation {
                        codexThreads[continuation.segment] = continuation.thread
                    }
                    for record in saved.records { merge(record) }
                }
            }
        }
        cache = cache.filter { alive.contains($0.key) }
        // 分段文件的 UUID 不是对话 ID。源日志确认归属后，同时纠正已保存历史，
        // 保留原去重键（含无累计签名时的分段 ID）、时间和 Token，避免重复入账。
        for (id, var record) in records {
            if let thread = codexThreads[record.session] {
                record.session = thread
                records[id] = record
            }
        }
        result.records = records.values.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        // 仍可确认的目录每轮更新归属；已删除的 worktree 沿用之前确认的主项目。
        for project in Set(result.records.map(\.project)) {
            result.projectRoots[project] = ProjectWorktreeResolver.mainProjectPath(for: project) ?? history.projectRoots[project]
        }
        if historyLoaded {
            // 只更新 Codex 记录；旧版保存的其他服务历史及元数据原样保留。
            history.records.merge(records) { _, current in current }
            history.projectRoots.merge(result.projectRoots) { _, current in current }
            if history != savedHistory {
                do {
                    try historyStore.save(history)
                    savedHistory = history
                } catch {
                    result.historyError = "历史保存失败，新增用量暂仅保留在内存；下次刷新会重试。"
                }
            }
        }
        if failures > 0 { result.warnings.append("\(failures) 处日志无法读取，统计可能不完整") }
        if invalid > 0 { result.warnings.append("\(invalid) 条记录格式无效，已跳过") }
        return result
    }

    private func parse(_ file: URL, size: Int, modified: Date) throws -> CachedFile {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        var records: [UsageRecord] = []
        var invalid = 0
        let isCompressed = file.pathExtension == "zst"
        // 压缩副本使用同一个会话 ID，尤其是缺少累计签名时的行号去重键。
        let jsonlFile = isCompressed ? file.deletingPathExtension() : file
        let filename = jsonlFile.deletingPathExtension().lastPathComponent
        let filenameID = String(filename.suffix(36))
        let filenameUUID = UUID(uuidString: filenameID)
        var session = filenameUUID == nil ? filename : filenameID
        var codexContinuation: (segment: String, thread: String)?
        var emitter = session
        var project = ""
        var model = "未知模型"
        var sawMeta = false
        var serviceTier = "standard"
        var serviceTierReported = false
        var timer = CodexRequestTimer()
        var previousSignature: String?
        var lineNumber = 0

        func consume(_ line: Data) {
            lineNumber += 1
            guard !line.isEmpty else { return }
            guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { invalid += 1; return }
            let type = row["type"] as? String
            let payload = row["payload"] as? [String: Any] ?? [:]
            let date = (row["timestamp"] as? String).flatMap { fractional.date(from: $0) ?? whole.date(from: $0) }
            if type == "session_meta" {
                emitter = payload["id"] as? String ?? payload["session_id"] as? String ?? emitter
                if !sawMeta {
                    project = payload["cwd"] as? String ?? ""
                    if filenameUUID == nil { session = emitter }
                    // rollout-…-<threadID>_<segmentID>：只有文件名与首条元数据
                    // 指向同一线程时归并；之后 fork 重放的父线程元数据不改变归属。
                    let thread = String(filename.dropLast(37).suffix(36))
                    if filename.suffix(37).first == "_", filenameUUID != nil,
                       UUID(uuidString: thread) != nil, thread == emitter {
                        codexContinuation = (segment: filenameID, thread: thread)
                    }
                    sawMeta = true
                }
                return
            }
            if type == "turn_context" {
                model = payload["model"] as? String ?? model
                if let tier = payload["service_tier"] as? String {
                    serviceTier = tier
                    serviceTierReported = true
                }
                if let date { timer.boundary = max(timer.boundary ?? date, date) }
                return
            }
            if type == "event_msg", payload["type"] as? String == "thread_settings_applied" {
                let settings = payload["thread_settings"] as? [String: Any] ?? payload
                model = settings["model"] as? String ?? model
                serviceTier = settings["service_tier"] as? String ?? "unknown"
                serviceTierReported = settings["service_tier"] is String
                return
            }
            if let date {
                if type == "response_item", let item = payload["type"] as? String {
                    if item == "message", payload["role"] as? String != "assistant" {
                        timer.boundary = max(timer.boundary ?? date, date)
                    } else if item.hasSuffix("_output") {
                        timer.boundary = max(timer.boundary ?? date, date)
                        if timer.lastOutput != nil { timer.toolOutputAfterModel = date }
                    } else if item == "message" || item == "reasoning" || item.hasSuffix("_call") {
                        timer.observeOutput(at: date, isToolCall: item.hasSuffix("_call"))
                    }
                } else if type == "token_usage_record", let usage = payload["usage"] as? [String: Any],
                          let tokens = tokenCounts(usage) {
                    timer.usageRecord = (date, tokens)
                } else if type == "event_msg" {
                    switch payload["type"] as? String {
                    case "task_started", "turn_aborted": timer.reset(at: date)
                    case "item_completed":
                        if let item = payload["item"] as? [String: Any],
                           ["Reasoning", "AgentMessage"].contains(item["type"] as? String ?? ""),
                           let stamp = payload["started_at_ms"] as? NSNumber,
                           CFGetTypeID(stamp) != CFBooleanGetTypeID(), stamp.doubleValue.isFinite,
                           stamp.doubleValue > 0, stamp.doubleValue <= date.timeIntervalSince1970 * 1000 {
                            let started = Date(timeIntervalSince1970: stamp.doubleValue / 1000)
                            timer.firstOutput = min(timer.firstOutput ?? started, started)
                        }
                    default: break
                    }
                }
            }
            guard type == "event_msg", payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let usage = info["last_token_usage"] as? [String: Any] else { return }
            let total = info["total_token_usage"] as? [String: Any]
            let signature = total.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                .map { String(decoding: $0, as: UTF8.self) }
            if let signature, signature == previousSignature { return }
            previousSignature = signature
            guard let tokens = tokenCounts(usage) else { invalid += 1; return }
            let timing = timer.finish(at: date, tokens: tokens)
            guard tokens.total > 0 else { return }
            guard let date else { invalid += 1; return }
            records.append(UsageRecord(id: "codex:\(emitter):\(signature ?? "\(session):\(lineNumber)")",
                                       service: .codex, session: session, project: project,
                                       model: model, date: date, tokens: tokens,
                                       serviceTier: serviceTier.lowercased(), isUSOnly: false,
                                       serviceTierReported: serviceTierReported,
                                       estimatedDuration: timing?.duration, estimatedFirstToken: timing?.firstToken))
        }

        // ponytail: 变更文件从头解析；若单个日志增长到影响刷新，再改为 byte-offset 增量读取。
        var pending = Data()
        func consumeChunk(_ chunk: Data) {
            pending.append(chunk)
            var start = pending.startIndex
            while let end = pending[start...].firstIndex(of: 10) {
                consume(pending.subdata(in: start..<end))
                start = end + 1
            }
            if start > pending.startIndex { pending = Data(pending[start...]) }
        }
        if isCompressed {
            try ZstdStreamReader.forEachChunk(in: handle, consume: consumeChunk)
        } else {
            while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                autoreleasepool { consumeChunk(chunk) }
            }
        }
        // 普通日志正在写入的末行留到下次刷新；压缩归档的无效末行仍应提示。
        if !pending.isEmpty, isCompressed || (try? JSONSerialization.jsonObject(with: pending)) != nil { consume(pending) }
        return CachedFile(size: size, modified: modified, records: records, invalidLines: invalid,
            codexContinuation: codexContinuation)
    }

    private func tokenCounts(_ values: [String: Any]) -> UsageTokens? {
        func count(_ key: String) -> Int? {
            guard let value = values[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            let number = value.doubleValue
            guard number.isFinite, number >= 0, number < Double(Int.max / 16), number.rounded(.down) == number else { return nil }
            return value.intValue
        }
        guard let input = count("input_tokens"), let output = count("output_tokens") else { return nil }
        var tokens = UsageTokens()
        tokens.output = output
        tokens.cached = count("cached_input_tokens") ?? count("cache_read_input_tokens") ?? 0
        let cacheWrite = count("cache_write_input_tokens") ?? count("cache_write_tokens")
        tokens.cacheWrite = cacheWrite ?? 0
        tokens.cacheWriteReported = cacheWrite != nil
        guard tokens.cached + tokens.cacheWrite <= input else { return nil }
        tokens.input = input - tokens.cached - tokens.cacheWrite
        // Codex 聚合计数未提供缓存保留期，按短保留期作 API 参考估算。
        return tokens
    }
}

// Timing boundaries adapted from farion1231/cc-switch (MIT), session_usage_codex.rs.
// Copyright (c) 2025 Jason Young. See Resources/ThirdPartyNotices/cc-switch-LICENSE.txt.
private struct CodexRequestTimer {
    var boundary: Date?
    var lastTokenCount: Date?
    var start: Date?
    var lastOutput: Date?
    var toolOutputAfterModel: Date?
    var usageRecord: (date: Date, tokens: UsageTokens)?
    var firstOutput: Date?
    var startsWithToolCall = false

    mutating func observeOutput(at date: Date, isToolCall: Bool) {
        // 旧布局会在 token_count 之后同批补写上一条响应，不把它当成新请求。
        if start == nil, let lastTokenCount, date.timeIntervalSince(lastTokenCount) <= 0.1 { return }
        if lastOutput == nil {
            start = boundary
            startsWithToolCall = isToolCall
        }
        lastOutput = date
        toolOutputAfterModel = nil
    }

    mutating func reset(at date: Date?) {
        self = CodexRequestTimer(boundary: [boundary, date].compactMap { $0 }.max(), lastTokenCount: lastTokenCount)
    }

    mutating func finish(at date: Date?, tokens: UsageTokens) -> (duration: TimeInterval, firstToken: TimeInterval?)? {
        defer {
            reset(at: date)
            lastTokenCount = date
        }
        guard let start = start ?? boundary else { return nil }
        let end: Date?
        if let usageRecord,
           usageRecord.tokens.input + usageRecord.tokens.cacheWrite == tokens.input + tokens.cacheWrite,
           usageRecord.tokens.cached == tokens.cached, usageRecord.tokens.output == tokens.output {
            end = usageRecord.date
        } else if let toolOutputAfterModel, date.map({ $0.timeIntervalSince(toolOutputAfterModel) <= 0.1 }) ?? true {
            // 旧版等工具执行完才写 token_count，用最后一个模型输出项排除工具耗时。
            end = lastOutput
        } else {
            end = date
        }
        guard let end else { return nil }
        let duration = end.timeIntervalSince(start)
        // 日志缺少可靠边界时不猜测；与上游相同，超过一小时不作请求耗时。
        guard duration > 0, duration <= 3600 else { return nil }
        let firstToken = startsWithToolCall ? nil : firstOutput.map { $0.timeIntervalSince(start) }
        return (duration, firstToken.flatMap { $0 > 0 && $0 <= duration ? $0 : nil })
    }
}
