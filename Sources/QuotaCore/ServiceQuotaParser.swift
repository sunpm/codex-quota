// Response shapes reference nanvon/cc-bar and steipete/CodexBar (MIT).
// See THIRD_PARTY_NOTICES.md. Missing measurements are never treated as zero usage.
import Foundation
import CoreFoundation

public enum ServiceQuotaParser {
    public static func claude(_ data: Data) throws -> [QuotaWindow] {
        let root = try object(data)
        var windows: [String: QuotaWindow] = [:]
        let legacy: [(String, String, Int)] = [
            ("five_hour", "5 小时额度", 300), ("seven_day", "7 天额度", 10080),
            ("seven_day_opus", "Opus · 7 天", 10080), ("seven_day_sonnet", "Sonnet · 7 天", 10080)
        ]
        for (key, label, duration) in legacy {
            guard let value = root[key] as? [String: Any], let used = percent(value["utilization"]) else { continue }
            windows[key] = window(.claude, id: key, used: used, label: label, duration: duration, reset: date(value["resets_at"]))
        }
        for row in root["limits"] as? [[String: Any]] ?? [] {
            guard let kind = row["kind"] as? String else { continue }
            let key: String
            let label: String
            let duration: Int
            switch kind {
            case "session": key = "five_hour"; label = "5 小时额度"; duration = 300
            case "weekly_all": key = "seven_day"; label = "7 天额度"; duration = 10080
            case "weekly_scoped":
                let scope = row["scope"] as? [String: Any] ?? [:]
                let model = scope["model"] as? [String: Any] ?? scope["surface"] as? [String: Any] ?? [:]
                guard let name = nonEmpty(model["display_name"] ?? model["name"] ?? scope["surface"]) else { continue }
                let identity = nonEmpty(model["id"]) ?? name
                if name.lowercased().contains("opus") { key = "seven_day_opus" }
                else if name.lowercased().contains("sonnet") { key = "seven_day_sonnet" }
                else { key = "scoped:\(identity)" }
                label = "\(name) · 7 天"; duration = 10080
            default: continue
            }
            if row["is_active"] as? Bool == false { windows[key] = nil; continue }
            guard let used = percent(row["percent"]) else { continue }
            windows[key] = window(.claude, id: key, used: used, label: label, duration: duration,
                                  reset: date(row["resets_at"]) ?? windows[key]?.resetsAt)
        }
        return windows.values.sorted {
            let order = ["claude:five_hour", "claude:seven_day"]
            let lhs = order.firstIndex(of: $0.id) ?? 2, rhs = order.firstIndex(of: $1.id) ?? 2
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }

    public static func cursor(_ data: Data) throws -> [QuotaWindow] {
        let root = try object(data)
        let individual = root["individualUsage"] as? [String: Any] ?? [:]
        let plan = individual["plan"] as? [String: Any] ?? [:]
        let overall = individual["overall"] as? [String: Any] ?? [:]
        let team = root["teamUsage"] as? [String: Any] ?? [:]
        let pooled = team["pooled"] as? [String: Any] ?? [:]
        let reset = date(root["billingCycleEnd"])
        let start = date(root["billingCycleStart"])
        let duration: Int? = start.flatMap { start in
            guard let reset, reset > start else { return nil }
            let minutes = reset.timeIntervalSince(start) / 60
            return minutes < Double(Int.max) ? Int(minutes) : nil
        }
        let total: Double?
        if root["limitType"] as? String == "team" { total = ratio(pooled) }
        else if plan["enabled"] as? Bool == false { total = nil }
        else { total = nonnegative(plan["totalPercentUsed"]) ?? ratio(plan) ?? ratio(overall) }
        let values: [(String, String, Double?)] = [
            ("total", "账期总额度", total),
            ("auto", "Auto", plan["enabled"] as? Bool == false ? nil : nonnegative(plan["autoPercentUsed"])),
            ("api", "API", plan["enabled"] as? Bool == false ? nil : nonnegative(plan["apiPercentUsed"]))
        ]
        return values.compactMap { id, label, used in
            guard let used else { return nil }
            return window(.cursor, id: id, used: min(100, used), label: label, duration: duration, reset: reset)
        }
    }

    public static func antigravitySummary(_ data: Data) throws -> [QuotaWindow] {
        let root = try object(data)
        guard success(root) else { return [] }
        let payload = root["response"] as? [String: Any] ?? root["summary"] as? [String: Any] ?? root
        var windows: [QuotaWindow] = []
        for group in payload["groups"] as? [[String: Any]] ?? [] {
            let name = nonEmpty(group["displayName"] ?? group["name"]) ?? "模型组"
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard bucket["disabled"] as? Bool != true,
                      let id = nonEmpty(bucket["bucketId"] ?? bucket["id"]) else { continue }
                let remaining = bucket["remaining"] as? [String: Any] ?? [:]
                let oneof = remaining["case"] as? String == "remainingFraction" ? remaining["value"] : nil
                guard let fraction = number(bucket["remainingFraction"] ?? remaining["remainingFraction"] ?? oneof),
                      (0...1).contains(fraction) else { continue }
                let label = nonEmpty(bucket["displayName"] ?? bucket["name"]) ?? id
                windows.append(window(.antigravity, id: "\(name):\(id)", used: (1 - fraction) * 100,
                                      label: "\(name) · \(label)", reset: date(bucket["resetTime"])))
            }
        }
        return unique(windows)
    }

    public static func antigravityStatus(_ data: Data) throws -> [QuotaWindow] {
        let root = try object(data)
        guard success(root) else { return [] }
        let status = root["userStatus"] as? [String: Any] ?? [:]
        let config = status["cascadeModelConfigData"] as? [String: Any] ?? [:]
        let rows = config["clientModelConfigs"] as? [[String: Any]] ?? []
        return unique(rows.compactMap { row in
            let model = row["modelOrAlias"] as? [String: Any] ?? [:]
            guard let id = nonEmpty(model["model"]), let label = nonEmpty(row["label"]),
                  let quota = row["quotaInfo"] as? [String: Any],
                  let fraction = number(quota["remainingFraction"]), (0...1).contains(fraction) else { return nil }
            return window(.antigravity, id: "model:\(id)", used: (1 - fraction) * 100, label: label, reset: date(quota["resetTime"]))
        })
    }

    public static func antigravityAccount(_ data: Data) throws -> String? {
        let root = try object(data)
        guard success(root) else { return nil }
        return nonEmpty((root["userStatus"] as? [String: Any])?["email"])
    }

    public static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return value
    }

    public static func number(_ value: Any?) -> Double? {
        let result: Double?
        if let n = value as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            result = n.doubleValue
        } else if let s = value as? String { result = Double(s) }
        else { result = nil }
        guard let result, result.isFinite else { return nil }
        return result
    }

    public static func date(_ value: Any?) -> Date? {
        if let n = number(value) {
            guard n > 0, n < 100_000_000_000_000 else { return nil }
            return Date(timeIntervalSince1970: n > 10_000_000_000 ? n / 1000 : n)
        }
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    public static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func percent(_ value: Any?) -> Double? {
        guard let n = number(value), (0...100).contains(n) else { return nil }
        return n
    }
    private static func nonnegative(_ value: Any?) -> Double? {
        guard let n = number(value), n >= 0 else { return nil }
        return n
    }
    private static func ratio(_ bucket: [String: Any]) -> Double? {
        guard bucket["enabled"] as? Bool != false, let used = nonnegative(bucket["used"]),
              let limit = number(bucket["limit"]), limit > 0 else { return nil }
        let percent = used / limit * 100
        return percent.isFinite ? percent : nil
    }
    private static func window(_ service: QuotaService, id: String, used: Double, label: String, duration: Int? = nil, reset: Date?) -> QuotaWindow {
        QuotaWindow(id: "\(service.rawValue):\(id)", bucket: service.rawValue, name: service.title,
                    usedPercent: used, durationMinutes: duration, resetsAt: reset, label: label)
    }
    private static func unique(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        var seen: Set<String> = []
        return windows.filter { seen.insert($0.id).inserted }
    }
    private static func success(_ object: [String: Any]) -> Bool {
        guard let code = object["code"] else { return true }
        if let number = number(code) { return number == 0 }
        return ["ok", "success"].contains((code as? String ?? "").lowercased())
    }
}
