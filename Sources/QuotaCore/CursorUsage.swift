// Cursor Dashboard fields and pagination reference nanvon/cc-bar (MIT).
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import Foundation
import CoreFoundation

public struct CursorUsageEvent: Sendable {
    public let date: Date
    public let model: String
    public let tokens: UsageTokens?
    public let costUSD: Decimal?
}

public struct CursorUsagePage: Sendable {
    public let total: Int
    public let events: [CursorUsageEvent]

    /// 在响应边界解析一次；缺失的费用与 Token 不补成零。
    public static func decode(_ data: Data) throws -> Self {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let total = integer(root["totalUsageEventsCount"]),
              let rows = root["usageEventsDisplay"] as? [[String: Any]] else {
            throw CursorUsageError.invalidResponse
        }
        let events = try rows.map { row -> CursorUsageEvent in
            guard let milliseconds = integer(row["timestamp"]), milliseconds > 0 else {
                throw CursorUsageError.invalidResponse
            }
            var tokens: UsageTokens?
            if let usage = row["tokenUsage"] as? [String: Any],
               let input = integer(usage["inputTokens"]), let output = integer(usage["outputTokens"]),
               let cached = integer(usage["cacheReadTokens"]), let write = integer(usage["cacheWriteTokens"]) {
                // 确保已验证的四类值可安全相加，内层不再检查原始 JSON。
                var sum = 0
                for value in [input, output, cached, write] {
                    let result = sum.addingReportingOverflow(value)
                    guard !result.overflow else { throw CursorUsageError.invalidResponse }
                    sum = result.partialValue
                }
                var value = UsageTokens()
                value.input = input; value.output = output; value.cached = cached; value.cacheWrite = write
                tokens = value
            }
            let model = (row["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CursorUsageEvent(date: Date(timeIntervalSince1970: Double(milliseconds) / 1_000),
                model: model.flatMap { $0.isEmpty ? nil : $0 } ?? "未知模型", tokens: tokens,
                costUSD: decimal(row["chargedCents"]).map { $0 / 100 })
        }
        return Self(total: total, events: events)
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        let text: String
        switch value {
        case let number as NSNumber:
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            text = number.stringValue
        case let string as String: text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        default: return nil
        }
        guard text.range(of: #"^\d+(\.\d+)?([eE][+-]?\d+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0 else { return nil }
        return value
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = decimal(value), number <= Decimal(Int.max) else { return nil }
        let integer = NSDecimalNumber(decimal: number).intValue
        return Decimal(integer) == number ? integer : nil
    }
}

public struct CursorUsageTotals: Sendable {
    public private(set) var requests = 0
    public private(set) var tokens: Decimal = 0
    public private(set) var missingTokens = 0
    public private(set) var cost = UsageCost()

    public init(events: [CursorUsageEvent]) {
        requests = events.count
        for event in events {
            if let value = event.tokens { tokens += Decimal(value.total) }
            else { missingTokens += 1 }
            cost.add(event.costUSD)
        }
    }
}

public enum CursorUsageError: LocalizedError {
    case invalidResponse, incompletePages, pageLimit

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Cursor 用量响应格式无效。"
        case .incompletePages: return "Cursor 分页数量不一致或数据不完整，请稍后刷新。"
        case .pageLimit: return "Cursor 用量超过单次查询上限，请缩小日期范围。"
        }
    }
}
