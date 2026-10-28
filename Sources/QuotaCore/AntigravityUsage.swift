// Transcript fields and token semantics adapted from farion1231/cc-switch (MIT).
// Copyright (c) 2025 Jason Young. See Resources/ThirdPartyNotices/cc-switch-LICENSE.txt.
import Foundation
import CoreFoundation

/// 仅提取已完成响应的计量字段，不保留正文，也不从当前模型设置推断历史。
struct AntigravityUsageParser {
    private enum Step {
        case pending, missingUsage, invalid
        case complete(UsageRecord)
    }

    private let session: String
    private let fractional: ISO8601DateFormatter
    private let whole = ISO8601DateFormatter()
    private var steps: [Int: Step] = [:]
    private var invalidRows = 0

    init(session: String) {
        self.session = session
        fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    var records: [UsageRecord] {
        steps.values.compactMap { if case .complete(let record) = $0 { return record }; return nil }
    }
    var missingUsageCount: Int {
        steps.values.reduce(0) { count, step in
            if case .missingUsage = step { return count + 1 }; return count
        }
    }
    var invalidCount: Int {
        invalidRows + steps.values.reduce(0) { count, step in
            if case .invalid = step { return count + 1 }; return count
        }
    }

    mutating func consume(_ row: [String: Any]) {
        guard row["type"] as? String == "PLANNER_RESPONSE" else { return }
        guard let index = Self.count(row["step_index"]) else { invalidRows += 1; return }
        // 同一步骤会重复导出，最后一条状态与计数生效，不能把快照当成新请求。
        guard row["status"] as? String == "DONE" else { steps[index] = .pending; return }
        guard row["input_tokens"] != nil, row["output_tokens"] != nil else {
            steps[index] = .missingUsage
            return
        }
        guard let input = Self.count(row["input_tokens"]), let output = Self.count(row["output_tokens"]),
              let cached = Self.count(row["cache_read_tokens"] ?? 0),
              let write = Self.count(row["cache_write_tokens"] ?? 0) else {
            steps[index] = .invalid
            return
        }
        let date: Date?
        if let stamp = row["created_at"] as? String {
            date = fractional.date(from: stamp) ?? whole.date(from: stamp)
        } else if let stamp = Self.count(row["created_at"]) {
            date = Date(timeIntervalSince1970: Double(stamp) / (stamp > 1_000_000_000_000 ? 1000 : 1))
        } else { date = nil }
        guard let date else { steps[index] = .invalid; return }
        let rawModel = (row["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = rawModel.flatMap { $0.isEmpty || $0.lowercased() == "unknown" ? nil : $0 } ?? "未知模型"
        var tokens = UsageTokens()
        // Antigravity 的 input 已排除缓存，output 已包含 reasoning；不再减缓存或加推理。
        tokens.input = input
        tokens.output = output
        tokens.cached = cached
        tokens.cacheWrite = write
        steps[index] = .complete(UsageRecord(id: "antigravity:\(session):\(index)", service: .antigravity,
            session: session, project: "", model: model, date: date, tokens: tokens,
            serviceTier: "standard", isUSOnly: false))
    }

    /// JSON 边界只接受非负整数，缺失、布尔值与无效计数不得变成零用量。
    private static func count(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let number = value.doubleValue
        guard number.isFinite, number >= 0, number < Double(Int.max / 16), number.rounded(.down) == number else { return nil }
        return value.intValue
    }
}
