import SwiftUI
import QuotaCore

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var scan = UsageScan()
    @Published private(set) var refreshing = false
    @Published private(set) var updatedAt: Date?
    @Published private(set) var prices: [String: ModelPricing] = [:]
    @Published private(set) var priceDate = BundledModelPrices.date
    @Published private(set) var updatingPrices = false
    @Published private(set) var pricingError: String?
    private let reader = LocalUsageReader()
    private let defaults: UserDefaults
    private var catalog: [String: ModelPricing]
    private var overrides: [String: ModelPricing]
    private var costs: [String: Decimal] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        catalog = defaults.data(forKey: "usage.pricing.catalog.v1")
            .flatMap { try? decoder.decode([String: ModelPricing].self, from: $0) }
            ?? (try? UsagePricing.decodeCatalog(BundledModelPrices.data)) ?? [:]
        overrides = defaults.data(forKey: "usage.pricing.overrides.v1")
            .flatMap { try? decoder.decode([String: ModelPricing].self, from: $0) } ?? [:]
        catalog = catalog.filter { $0.value.isValid }
        overrides = overrides.filter { $0.value.isValid }
        priceDate = defaults.string(forKey: "usage.pricing.date") ?? BundledModelPrices.date
        prices = catalog.merging(overrides) { _, custom in custom }
    }

    func cost(_ record: UsageRecord) -> Decimal? { costs[record.id] }
    func costTotal(_ records: [UsageRecord]) -> UsageCost {
        records.reduce(into: UsageCost()) { $0.add(cost($1)) }
    }
    func isCustom(_ price: ModelPricing) -> Bool { overrides[price.id] != nil }

    func savePrice(_ price: ModelPricing) {
        guard price.isValid else { return }
        overrides[price.id] = price
        persistOverrides()
    }
    func resetPrice(_ price: ModelPricing) {
        overrides.removeValue(forKey: price.id)
        persistOverrides()
    }
    private func persistOverrides() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: "usage.pricing.overrides.v1")
        prices = catalog.merging(overrides) { _, custom in custom }
        reprice()
    }
    private func reprice() {
        var resolved: [String: ModelPricing] = [:]
        for record in scan.records {
            let key = ModelPricing.key(record.service, record.model)
            if resolved[key] == nil, let price = UsagePricing.lookup(service: record.service, model: record.model, prices: prices) {
                resolved[key] = price
            }
        }
        costs = [:]
        for record in scan.records {
            costs[record.id] = resolved[ModelPricing.key(record.service, record.model)]?.cost(record)
        }
        objectWillChange.send()
    }

    func updatePrices() async {
        guard !updatingPrices else { return }
        updatingPrices = true
        defer { updatingPrices = false }
        do {
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            var request = URLRequest(url: URL(string: "https://models.dev/api.json")!)
            request.timeoutInterval = 30
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PricingError.invalidCatalog }
            let updated = try UsagePricing.decodeCatalog(data)
            let encoded = try JSONEncoder().encode(updated)
            catalog = updated
            priceDate = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
            defaults.set(encoded, forKey: "usage.pricing.catalog.v1")
            defaults.set(priceDate, forKey: "usage.pricing.date")
            prices = catalog.merging(overrides) { _, custom in custom }
            reprice()
            pricingError = nil
        } catch { pricingError = "更新失败，已保留原有价格：\(error.localizedDescription)" }
    }


    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let result = await reader.scan()
        scan = result
        reprice()
        updatedAt = Date()
        refreshing = false
    }
}

enum PanelPage: String, CaseIterable, Identifiable {
    case overview = "概览", sessions = "对话", projects = "项目", quota = "额度", settings = "设置"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .sessions: return "bubble.left.and.bubble.right"
        case .projects: return "folder"
        case .quota: return "gauge.medium"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class PanelNavigation: ObservableObject {
    @Published var page: PanelPage
    init(page: PanelPage = .overview) { self.page = page }
}

private enum UsageRange: String, CaseIterable {
    case today = "今天", yesterday = "昨天", week = "7 天", month = "30 天", all = "全部", custom = "自定义"
    var hourly: Bool { self == .today || self == .yesterday }

    func intervals(now: Date, customStart: Date, customEnd: Date) -> (current: DateInterval, previous: DateInterval?) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start: Date
        switch self {
        case .today: start = today
        case .yesterday: start = calendar.date(byAdding: .day, value: -1, to: today)!
        case .week: start = calendar.date(byAdding: .day, value: -6, to: today)!
        case .month: start = calendar.date(byAdding: .day, value: -29, to: today)!
        case .all: return (DateInterval(start: .distantPast, end: now), nil)
        case .custom: start = calendar.startOfDay(for: customStart)
        }
        let fullEnd = self == .yesterday ? today
            : calendar.date(byAdding: .day, value: 1, to: self == .custom ? calendar.startOfDay(for: customEnd) : today)!
        let end = max(start, min(fullEnd, now))
        let current = DateInterval(start: start, end: end)
        guard end > start else { return (current, nil) }
        let days = calendar.dateComponents([.day], from: start, to: fullEnd).day!
        // 按自然日平移，进行中的范围保留同一当地截止时刻；不把一天固定成 86400 秒。
        let previous = DateInterval(start: calendar.date(byAdding: .day, value: -days, to: start)!,
                                    end: calendar.date(byAdding: .day, value: -days, to: end)!)
        return (current, previous)
    }
}

private struct UsageGroup: Identifiable {
    let id: String
    let name: String
    let detail: String
    var tokens = UsageTokens()
    var cost = UsageCost()
}

struct UsageView: View {
    @ObservedObject var model: UsageModel
    let service: QuotaService?
    let page: PanelPage
    @State private var range: UsageRange = .month
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
    @State private var customEnd = Date()
    @State private var grouping = "模型"
    @State private var metric = "Tokens"
    @State private var selectedSession: UsageGroup?

    private func records(in interval: DateInterval) -> [UsageRecord] {
        model.scan.records.filter {
            (service == nil || $0.service == service) && $0.date >= interval.start && $0.date < interval.end
        }
    }
    private func total(_ records: [UsageRecord]) -> UsageTokens {
        records.reduce(into: UsageTokens()) { $0.add($1.tokens) }
    }
    private func groups(_ records: [UsageRecord], by kind: String) -> [UsageGroup] {
        var result: [String: UsageGroup] = [:]
        for record in records {
            let key: String
            let name: String
            let detail: String
            switch kind {
            case "服务":
                key = record.service.rawValue; name = record.service.title; detail = ""
            case "项目":
                key = model.scan.projectPath(for: record.project); name = projectName(key); detail = key
            case "对话":
                key = record.service.rawValue + record.session
                name = "\(record.service.title) · \(record.session.prefix(8))"
                detail = projectName(model.scan.projectPath(for: record.project))
            default:
                key = record.service.rawValue + ":" + record.model; name = record.model; detail = record.service.title
            }
            var group = result[key] ?? UsageGroup(id: key, name: name, detail: detail)
            group.tokens.add(record.tokens)
            group.cost.add(model.cost(record))
            result[key] = group
        }
        return result.values.sorted {
            let left = metric == "费用" ? $0.cost.amount : Decimal($0.tokens.total)
            let right = metric == "费用" ? $1.cost.amount : Decimal($1.tokens.total)
            return left == right ? $0.id < $1.id : left > right
        }
    }

    var body: some View {
        // 汇总、图表和比较共用同一截止时刻与筛选，避免临界时刻口径不同。
        let intervals = range.intervals(now: Date(), customStart: customStart, customEnd: customEnd)
        let records = records(in: intervals.current)
        let tokens = total(records)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(service?.title ?? "全部服务").foregroundStyle(.secondary)
                Spacer()
                Picker("时间范围", selection: $range) {
                    ForEach(UsageRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 420)
            }
            if range == .custom {
                HStack {
                    DatePicker("开始", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                    DatePicker("结束", selection: $customEnd, in: customStart..., displayedComponents: .date)
                }
            }
            if service == .antigravity || service == .cursor {
                empty("暂无本地 Token 数据", detail: "\(service!.title) 目前支持剩余额度查询，可在“额度”中查看。")
            } else if model.updatedAt == nil {
                ProgressView("正在读取本地用量…").frame(maxWidth: .infinity, minHeight: 260)
            } else if records.isEmpty && page != .overview {
                summary(records, tokens: tokens, previous: intervals.previous)
                empty("所选范围内没有用量", detail: "统计 Codex 和 Claude Code 保存在本机的会话记录。")
            } else if page == .overview {
                summary(records, tokens: tokens, previous: intervals.previous)
                UsageHeatmapView(model: model, service: service)
                if records.isEmpty {
                    empty("所选范围内没有用量", detail: "统计 Codex 和 Claude Code 保存在本机的会话记录。")
                } else {
                    chart(records, interval: intervals.current)
                    HStack(alignment: .top, spacing: 18) {
                        composition(tokens).frame(maxWidth: .infinity)
                        ranking(Array(groups(records, by: "对话").prefix(5)), title: "高消耗对话")
                            .frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("用量构成").font(.headline)
                            Spacer()
                            Picker("分组", selection: $grouping) {
                                ForEach(["服务", "模型", "项目"], id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                        }
                        groupTable(groups(records, by: grouping), total: tokens.total, cost: model.costTotal(records))
                    }.padding(18).panelCard()
                }
            } else {
                summary(records, tokens: tokens, previous: intervals.previous)
                VStack(alignment: .leading, spacing: 12) {
                    Text(page.rawValue).font(.headline)
                    groupTable(groups(records, by: page.rawValue), total: tokens.total, cost: model.costTotal(records),
                               opensSession: page == .sessions)
                }.padding(18).panelCard()
            }
            let costs = model.costTotal(records)
            if costs.unpricedCount > 0 {
                Text("\(costs.unpricedCount) 条用量尚未定价，金额仅含已定价部分。可在设置中补充模型单价或档位。")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("API 等价估算 · USD · 不代表订阅账单")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.scan.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
            }
            HStack {
                Text("本机日志 · Codex / Claude Code")
                Spacer()
                if let updated = model.updatedAt { Text(updated, format: .dateTime.hour().minute()).monospacedDigit() }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(item: $selectedSession) { session in
            UsageSessionDetailView(model: model, title: session.name,
                range: range == .custom
                    ? customStart.formatted(date: .numeric, time: .omitted) + " – " + customEnd.formatted(date: .numeric, time: .omitted)
                    : range.rawValue,
                records: records.filter { $0.service.rawValue + $0.session == session.id })
        }
    }

    private func summary(_ records: [UsageRecord], tokens: UsageTokens, previous: DateInterval?) -> some View {
        let previousRecords = previous.map { self.records(in: $0) }
        let previousTokens = previousRecords.map { total($0).total }
        let cost = model.costTotal(records)
        let previousCost = previousRecords.map { model.costTotal($0) }
        return VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                metricCard("总 Tokens", value: formattedTokens(tokens.total),
                    change: previousTokens.map { change(current: Decimal(tokens.total), previous: Decimal($0), money: false) },
                    previous: previousTokens.map { "\($0.formatted()) Tokens" })
                metricCard("估算费用", value: records.isEmpty ? "$0.00" : formattedCost(cost),
                    change: previousCost.map {
                        cost.unpricedCount > 0 || $0.unpricedCount > 0 ? "含未定价，暂不比较"
                            : change(current: cost.amount, previous: $0.amount, money: true)
                    }, previous: previousCost.map { $0.pricedCount == 0 && $0.unpricedCount == 0 ? "$0.00" : formattedCost($0) })
                metricCard("对话", value: Set(records.map { $0.service.rawValue + $0.session }).count.formatted())
                metricCard("输入缓存命中率", value: tokens.cacheHitRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
            }
            if let previous {
                Text("对比 \(previous.start.formatted(date: .numeric, time: .shortened)) – \(previous.end.formatted(date: .numeric, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
    private func metricCard(_ label: String, value: String, change: String? = nil, previous: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let change {
                Text(change).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .help(previous.map { "上期：\($0)" } ?? "")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16).panelCard()
    }
    private func change(current: Decimal, previous: Decimal, money: Bool) -> String {
        let delta = current - previous
        guard delta != 0 else { return "较上期持平" }
        let magnitude = abs(delta)
        let amount: String
        if money {
            var cost = UsageCost(); cost.add(magnitude)
            amount = formattedCost(cost)
        } else { amount = formattedTokens(NSDecimalNumber(decimal: magnitude).intValue) }
        guard previous > 0 else { return "较上期新增 \(amount)" }
        let sign = delta > 0 ? "+" : "−"
        let percent = NSDecimalNumber(decimal: magnitude / previous).doubleValue.formatted(.percent.precision(.fractionLength(1)))
        return "\(sign)\(percent) · \(sign)\(amount)"
    }
    private func chart(_ records: [UsageRecord], interval: DateInterval) -> some View {
        let calendar = Calendar.current
        let unit: Calendar.Component = range.hourly ? .hour : .day
        let buckets = Dictionary(grouping: records) { calendar.dateInterval(of: unit, for: $0.date)!.start }
        let start = range == .all ? buckets.keys.min() ?? calendar.startOfDay(for: interval.end) : interval.start
        // 当前未结束的小时 / 天也展示完整柱宽；未来时间只留空，不补造读数。
        let endDay = calendar.dateInterval(of: .day, for: range == .all ? buckets.keys.max() ?? interval.end : interval.end)!
        let end = range != .all && interval.end == endDay.start ? endDay.start : endDay.end
        return UsageTrendView(model: model, buckets: buckets, hourly: range.hourly,
                              interval: DateInterval(start: start, end: end), metric: $metric)
    }
    private func composition(_ tokens: UsageTokens) -> some View {
        let parts: [(String, Int, Color)] = [("输入", tokens.input, .blue), ("输出", tokens.output, .purple),
            ("缓存读取", tokens.cached, .teal), ("缓存写入", tokens.cacheWrite, .orange)]
        return VStack(alignment: .leading, spacing: 16) {
            Text("Token 拆分").font(.headline)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(parts, id: \.0) { part in
                        part.2.frame(width: geometry.size.width * Double(part.1) / Double(max(1, tokens.total)))
                    }
                }.clipShape(Capsule())
            }.frame(height: 8)
            ForEach(parts, id: \.0) { part in
                HStack {
                    Circle().fill(part.2).frame(width: 7, height: 7)
                    Text(part.0)
                    Spacer()
                    Text(formattedTokens(part.1)).monospacedDigit()
                    Text((Double(part.1) / Double(max(1, tokens.total))).formatted(.percent.precision(.fractionLength(1))))
                        .foregroundStyle(.secondary).monospacedDigit().frame(width: 52, alignment: .trailing)
                }.font(.callout)
            }
        }.padding(18).panelCard()
    }
    private func ranking(_ groups: [UsageGroup], title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(groups) { group in
                Button { selectedSession = group } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name).lineLimit(1)
                            Text(group.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(formattedCost(group.cost))
                            Text(formattedTokens(group.tokens.total) + " Tokens").font(.caption).foregroundStyle(.secondary)
                        }.monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.font(.callout).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(18).panelCard()
    }
    private func groupTable(_ groups: [UsageGroup], total: Int, cost: UsageCost, opensSession: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("名称"); Spacer()
                Text("Tokens").frame(width: 100, alignment: .trailing)
                Text("估算费用").frame(width: 100, alignment: .trailing)
                Text(metric == "费用" ? "费用占比" : "Token 占比").frame(width: 70, alignment: .trailing)
                Text("缓存命中率").frame(width: 86, alignment: .trailing)
                if opensSession { Color.clear.frame(width: 8, height: 1) }
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            ForEach(groups) { group in
                Divider()
                let row = HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name).fontWeight(.medium).lineLimit(1).help(group.detail.isEmpty ? group.name : group.detail)
                        if !group.detail.isEmpty { Text(group.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    Text(formattedTokens(group.tokens.total)).frame(width: 100, alignment: .trailing)
                    Text(formattedCost(group.cost)).frame(width: 100, alignment: .trailing)
                    Text(share(group, tokens: total, cost: cost)).frame(width: 70, alignment: .trailing)
                    Text(group.tokens.cacheHitRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
                        .frame(width: 86, alignment: .trailing)
                    if opensSession {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).frame(width: 8)
                    }
                }.font(.callout).monospacedDigit().padding(.vertical, 11).contentShape(Rectangle())
                if opensSession {
                    Button { selectedSession = group } label: { row }.buttonStyle(.plain)
                } else {
                    row
                }
            }
        }
    }
    private func share(_ group: UsageGroup, tokens: Int, cost: UsageCost) -> String {
        if metric == "费用" {
            guard cost.amount > 0, cost.unpricedCount == 0 else { return "—" }
            return NSDecimalNumber(decimal: group.cost.amount / cost.amount).doubleValue.formatted(.percent.precision(.fractionLength(1)))
        }
        return (Double(group.tokens.total) / Double(max(1, tokens))).formatted(.percent.precision(.fractionLength(1)))
    }

    private func empty(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 280)
    }
    private func projectName(_ path: String) -> String { path.isEmpty ? "未归属项目" : URL(fileURLWithPath: path).lastPathComponent }
}

func formattedTokens(_ value: Int) -> String {
    if value >= 100_000_000 { return (Double(value) / 100_000_000).formatted(.number.precision(.fractionLength(0...2))) + " 亿" }
    if value >= 10_000 { return (Double(value) / 10_000).formatted(.number.precision(.fractionLength(0...2))) + " 万" }
    return value.formatted()
}

extension View {
    func panelCard() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

func formattedCost(_ cost: UsageCost) -> String {
    guard cost.pricedCount > 0 else { return cost.unpricedCount > 0 ? "未定价" : "—" }
    let amount = cost.amount > 0 && cost.amount < Decimal(string: "0.01")!
        ? "< $0.01" : cost.amount.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    return cost.unpricedCount > 0 ? amount + "（部分）" : amount
}
