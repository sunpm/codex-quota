// Cost semantics adapted from farion1231/cc-switch (MIT).
// Copyright (c) 2025 Jason Young. See Resources/ThirdPartyNotices/cc-switch-LICENSE.txt.
import Foundation
import CoreFoundation

public struct TokenRates: Codable, Sendable {
    public var input: Decimal?
    public var output: Decimal?
    public var cached: Decimal?
    public var cacheWrite: Decimal?
    public var cacheWriteLong: Decimal?

    public init(input: Decimal? = nil, output: Decimal? = nil, cached: Decimal? = nil,
                cacheWrite: Decimal? = nil, cacheWriteLong: Decimal? = nil) {
        self.input = input; self.output = output; self.cached = cached
        self.cacheWrite = cacheWrite; self.cacheWriteLong = cacheWriteLong
    }

    public var isValid: Bool {
        [input, output, cached, cacheWrite, cacheWriteLong].allSatisfy { value in
            value.map { !$0.isNaN && $0 >= 0 && $0 < 1_000_000_000 } ?? true
        }
    }

    func cost(_ tokens: UsageTokens) -> Decimal? {
        let parts = [(tokens.input, input), (tokens.output, output), (tokens.cached, cached),
                     (tokens.cacheWrite - tokens.cacheWriteLong, cacheWrite), (tokens.cacheWriteLong, cacheWriteLong)]
        var result: Decimal = 0
        for (count, price) in parts where count > 0 {
            guard let price else { return nil }
            result += Decimal(count) * price / 1_000_000
        }
        return result
    }
}

public struct ModelPricing: Codable, Identifiable, Sendable {
    public var service: QuotaService
    public var model: String
    public var rates: TokenRates
    public var contextThreshold: Int?
    public var longContextRates: TokenRates?
    public var fastMultiplier: Decimal?
    public var ultrafastMultiplier: Decimal?
    public var id: String { Self.key(service, model) }

    public init(service: QuotaService, model: String, rates: TokenRates = TokenRates(),
                contextThreshold: Int? = nil, longContextRates: TokenRates? = nil,
                fastMultiplier: Decimal? = nil, ultrafastMultiplier: Decimal? = nil) {
        self.service = service; self.model = model; self.rates = rates
        self.contextThreshold = contextThreshold; self.longContextRates = longContextRates
        self.fastMultiplier = fastMultiplier; self.ultrafastMultiplier = ultrafastMultiplier
    }

    public static func key(_ service: QuotaService, _ model: String) -> String { service.rawValue + ":" + model.lowercased() }
    public var isValid: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rates.isValid
            && (longContextRates?.isValid ?? true)
            && (contextThreshold.map { $0 > 0 && $0 < 100_000_000 } ?? true)
            && [fastMultiplier, ultrafastMultiplier].allSatisfy { $0.map { !$0.isNaN && $0 > 0 && $0 < 1000 } ?? true }
    }

    public func cost(_ record: UsageRecord) -> Decimal? {
        let incoming = record.tokens.input + record.tokens.cached + record.tokens.cacheWrite
        let selected: TokenRates
        if let threshold = contextThreshold, incoming > threshold {
            guard let longContextRates else { return nil }
            selected = longContextRates
        } else { selected = rates }
        guard let base = selected.cost(record.tokens) else { return nil }
        let multiplier: Decimal
        switch record.serviceTier {
        case "standard", "default", "auto": multiplier = 1
        case "fast", "priority":
            guard let fastMultiplier else { return nil }
            multiplier = fastMultiplier
        case "ultrafast":
            guard let ultrafastMultiplier else { return nil }
            multiplier = ultrafastMultiplier
        default: return nil
        }
        return base * multiplier * (record.isUSOnly ? Decimal(string: "1.1")! : 1)
    }
}

public struct UsageCost: Sendable {
    public var amount: Decimal = 0
    public var pricedCount = 0
    public var unpricedCount = 0
    public init() {}
    public mutating func add(_ amount: Decimal?) {
        if let amount { self.amount += amount; pricedCount += 1 }
        else { unpricedCount += 1 }
    }
}

public enum UsagePricing {
    /// 只规范化已知厂商前缀、Claude 版本小数和日期；不猜测 auto-review 等别名。
    public static func lookup(service: QuotaService, model: String, prices: [String: ModelPricing]) -> ModelPricing? {
        let raw = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = prices[ModelPricing.key(service, raw)] { return exact }
        var name = raw
        let prefix = service == .codex ? "openai/" : "anthropic/"
        if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        if service == .claude { name = name.replacingOccurrences(of: ".", with: "-") }
        if let exact = prices[ModelPricing.key(service, name)] { return exact }
        name = name.replacingOccurrences(of: #"-\d{4}-?\d{2}-?\d{2}$"#, with: "", options: .regularExpression)
        return prices[ModelPricing.key(service, name)]
    }

    /// models.dev 单位为 USD / 百万 Tokens；缺失字段保留 nil，不能当免费。
    public static func decodeCatalog(_ data: Data) throws -> [String: ModelPricing] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PricingError.invalidCatalog }
        var result: [String: ModelPricing] = [:]
        for (provider, service) in [("openai", QuotaService.codex), ("anthropic", .claude)] {
            guard let vendor = root[provider] as? [String: Any], let models = vendor["models"] as? [String: Any], !models.isEmpty else {
                throw PricingError.invalidCatalog
            }
            for (name, value) in models {
                guard let model = value as? [String: Any], let cost = model["cost"] as? [String: Any] else { continue }
                let output = (model["modalities"] as? [String: Any])?["output"] as? [String]
                guard output == nil || output == ["text"] else { continue }
                let rates = decodeRates(cost, service: service)
                guard rates.input != nil, rates.output != nil else { continue }
                var price = ModelPricing(service: service, model: name, rates: rates)
                let tiers = cost["tiers"] as? [[String: Any]] ?? []
                let context = tiers.first { ($0["tier"] as? [String: Any])?["type"] as? String == "context" }
                if let context, let threshold = (context["tier"] as? [String: Any])?["size"] as? Int, threshold > 0 {
                    price.contextThreshold = threshold
                    price.longContextRates = decodeRates(context, service: service)
                } else if let long = cost["context_over_200k"] as? [String: Any] {
                    price.contextThreshold = 200_000
                    price.longContextRates = decodeRates(long, service: service)
                }
                // 已核对的 Fast 档位；其他模型保留未定价，不外推倍率。
                if ["gpt-6-astra", "gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-luna"].contains(name)
                    || ["claude-opus-5-5", "claude-opus-5", "claude-opus-4-8"].contains(name) {
                    price.fastMultiplier = 2
                }
                if ["gpt-6-astra", "gpt-6.1-sol"].contains(name) { price.ultrafastMultiplier = 6 }
                if price.isValid { result[price.id] = price }
            }
        }
        guard !result.isEmpty else { throw PricingError.invalidCatalog }
        return result
    }

    private static func decodeRates(_ value: [String: Any], service: QuotaService) -> TokenRates {
        func rate(_ key: String) -> Decimal? {
            guard let number = value[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue < 1_000_000_000 else { return nil }
            return number.decimalValue
        }
        let write = rate("cache_write")
        // Claude 1h 是 5m 的 1.6 倍；OpenAI 12h 是 30m 的 2 倍。
        return TokenRates(input: rate("input"), output: rate("output"), cached: rate("cache_read"), cacheWrite: write,
                          cacheWriteLong: write.map { $0 * (service == .claude ? Decimal(string: "1.6")! : 2) })
    }
}

public enum PricingError: LocalizedError {
    case invalidCatalog
    public var errorDescription: String? { "价格数据无效，已保留原有价格。" }
}
