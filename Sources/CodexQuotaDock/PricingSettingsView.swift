import SwiftUI
import QuotaCore

struct PricingSettingsView: View {
    @ObservedObject var model: UsageModel
    @State private var search = ""
    @State private var editing: ModelPricing?

    private var rows: [ModelPricing] {
        var prices = model.prices
        for record in model.scan.records {
            let key = ModelPricing.key(record.service, record.model)
            if prices[key] == nil {
                var price = UsagePricing.lookup(service: record.service, model: record.model, prices: model.prices)
                    ?? ModelPricing(service: record.service, model: record.model)
                price.model = record.model
                prices[key] = price
            }
        }
        return prices.values.filter { search.isEmpty || $0.model.localizedCaseInsensitiveContains(search) }
            .sorted {
                $0.service == $1.service ? $0.model < $1.model
                    : QuotaService.allCases.firstIndex(of: $0.service)! < QuotaService.allCases.firstIndex(of: $1.service)!
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("模型定价").font(.headline)
                Spacer()
                if model.updatingPrices { ProgressView().controlSize(.small) }
                Button("更新价格") { Task { await model.updatePrices() } }.disabled(model.updatingPrices)
                Button("添加") { editing = ModelPricing(service: .codex, model: "") }
            }
            HStack {
                Link("models.dev", destination: URL(string: "https://models.dev")!)
                Text(model.priceDate)
                Spacer()
                Text("USD / 百万 Tokens")
            }.font(.caption).foregroundStyle(.secondary)
            TextField("搜索模型", text: $search)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { price in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(price.model).lineLimit(1).help(price.model)
                                Text(priceLabel(price)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("编辑") { editing = price }
                        }.padding(.vertical, 8)
                        Divider()
                    }
                }
            }.frame(height: 240)
            Text("更新公开价格会重算历史估算，保留自定义价格。金额不含订阅费及工具调用附加费。")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.pricingError { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .sheet(item: $editing) { price in
            PriceEditor(price: price, isCustom: model.isCustom(price), save: model.savePrice, reset: model.resetPrice)
        }
    }

    private func priceLabel(_ price: ModelPricing) -> String {
        let source = model.isCustom(price) ? "自定义" : price.rates.input == nil ? "未定价" : "公开价格"
        let input = price.rates.input.map { NSDecimalNumber(decimal: $0).stringValue } ?? "—"
        let output = price.rates.output.map { NSDecimalNumber(decimal: $0).stringValue } ?? "—"
        return "\(price.service.title) · \(source) · 输入 \(input) / 输出 \(output)"
    }
}

private struct PriceEditor: View {
    let price: ModelPricing
    let isCustom: Bool
    let save: (ModelPricing) -> Void
    let reset: (ModelPricing) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var service: QuotaService
    @State private var name: String
    @State private var rates: [String]
    @State private var longRates: [String]
    @State private var hasLongContext: Bool
    @State private var threshold: String
    @State private var fast: String
    @State private var ultrafast: String
    @State private var error: String?

    init(price: ModelPricing, isCustom: Bool, save: @escaping (ModelPricing) -> Void, reset: @escaping (ModelPricing) -> Void) {
        self.price = price; self.isCustom = isCustom; self.save = save; self.reset = reset
        _service = State(initialValue: price.service)
        _name = State(initialValue: price.model)
        _rates = State(initialValue: Self.fields(price.rates))
        _longRates = State(initialValue: Self.fields(price.longContextRates ?? TokenRates()))
        _hasLongContext = State(initialValue: price.contextThreshold != nil)
        _threshold = State(initialValue: price.contextThreshold.map(String.init) ?? "")
        _fast = State(initialValue: Self.text(price.fastMultiplier))
        _ultrafast = State(initialValue: Self.text(price.ultrafastMultiplier))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模型定价").font(.title3.weight(.semibold))
            ScrollView {
                Form {
                    Picker("服务", selection: $service) {
                        Text("Codex").tag(QuotaService.codex)
                        Text("Claude Code").tag(QuotaService.claude)
                        Text("Antigravity").tag(QuotaService.antigravity)
                    }.disabled(!price.model.isEmpty)
                    TextField("模型 ID", text: $name).disabled(!price.model.isEmpty)
                    Section("单价 · USD / 百万 Tokens") { rateFields($rates) }
                    Section("速度档位") {
                        TextField("Fast 倍率", text: $fast)
                        TextField("Ultrafast 倍率", text: $ultrafast)
                    }
                    Toggle("长上下文单独计价", isOn: $hasLongContext)
                    if hasLongContext {
                        TextField("输入超过（Tokens）", text: $threshold)
                        rateFields($longRates)
                    }
                }.textFieldStyle(.roundedBorder)
            }
            Text("留空表示未定价，0 表示免费。倍率作用于各类 Token；缺少速度或缓存保留期的日志按标准档、短保留期估算。")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                if isCustom {
                    Button("恢复公开价格") { reset(price); dismiss() }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: saveDraft).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 500, height: hasLongContext ? 690 : 550)
    }

    private func rateFields(_ values: Binding<[String]>) -> some View {
        let labels = ["输入", "输出", "缓存读取", service == .claude ? "缓存写入 · 5 分钟" : "缓存写入 · 30 分钟",
                      service == .claude ? "缓存写入 · 1 小时" : "缓存写入 · 12 小时"]
        return ForEach(labels.indices, id: \.self) { index in TextField(labels[index], text: values[index]) }
    }
    private static func text(_ value: Decimal?) -> String { value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "" }
    private static func fields(_ rates: TokenRates) -> [String] {
        [rates.input, rates.output, rates.cached, rates.cacheWrite, rates.cacheWriteLong].map(text)
    }
    private func parse(_ value: String) throws -> Decimal? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN, number >= 0, number < 1_000_000_000 else { throw PricingError.invalidCatalog }
        return number
    }
    private func parseRates(_ fields: [String]) throws -> TokenRates {
        let values = try fields.map(parse)
        return TokenRates(input: values[0], output: values[1], cached: values[2], cacheWrite: values[3], cacheWriteLong: values[4])
    }
    private func saveDraft() {
        do {
            let rates = try parseRates(rates)
            let contextLimit = hasLongContext ? Int(threshold.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
            guard !hasLongContext || contextLimit != nil else { throw PricingError.invalidCatalog }
            let draft = ModelPricing(service: service, model: name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                rates: rates, contextThreshold: contextLimit, longContextRates: hasLongContext ? try parseRates(longRates) : nil,
                fastMultiplier: try parse(fast), ultrafastMultiplier: try parse(ultrafast))
            guard draft.isValid else { throw PricingError.invalidCatalog }
            save(draft); dismiss()
        } catch { self.error = "请输入有效的模型 ID 和非负单价；上下文阈值、速度倍率必须大于 0。" }
    }
}
