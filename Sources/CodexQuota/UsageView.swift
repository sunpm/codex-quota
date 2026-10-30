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
    @Published private(set) var historyActionError: String?
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
        prices = catalog.merging(overrides) { _, custom in custom }.filter { $0.value.service == .codex }
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
        prices = catalog.merging(overrides) { _, custom in custom }.filter { $0.value.service == .codex }
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
            prices = catalog.merging(overrides) { _, custom in custom }.filter { $0.value.service == .codex }
            reprice()
            pricingError = nil
        } catch { pricingError = "更新失败，已保留原有价格：\(error.localizedDescription)" }
    }


    func refresh(rescan: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        apply(await reader.scan(rescan: rescan))
    }

    func clearHistory() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            try await reader.clearHistory()
            historyActionError = nil
            apply(await reader.scan())
        } catch {
            historyActionError = "清除失败，已保留原有历史。"
        }
    }

    private func apply(_ result: UsageScan) {
        scan = result
        reprice()
        updatedAt = Date()
    }
}

enum PanelPage: String, CaseIterable, Identifiable {
    case overview = "概览", sessions = "对话", projects = "项目", quota = "额度", settings = "设置"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "chart.xyaxis.line"
        case .sessions: return "bubble.left"
        case .projects: return "folder"
        case .quota: return "chart.pie"
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
    var latestUsage: Date?
    var tokens = UsageTokens()
    var cost = UsageCost()

    var subtitle: String {
        guard let latestUsage else { return detail }
        return "\(latestUsage.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())) · \(id.suffix(8))"
    }
}

struct UsageView: View {
    @ObservedObject var model: UsageModel
    let page: PanelPage
    @State private var range: UsageRange = .month
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
    @State private var customEnd = Date()
    @State private var showsCustomDates = false
    @State private var grouping = "模型"
    @State private var metric = "Tokens"
    @State private var selectedSession: UsageGroup?

    private func records(in interval: DateInterval) -> [UsageRecord] {
        model.scan.records.filter {
            $0.date >= interval.start && $0.date < interval.end
        }
    }
    private func total(_ records: [UsageRecord]) -> UsageTokens {
        records.reduce(into: UsageTokens()) { $0.add($1.tokens) }
    }
    private func groups(_ records: [UsageRecord], by kind: String) -> [UsageGroup] {
        let scan = model.scan
        var result: [String: UsageGroup] = [:]
        for record in records {
            let key: String
            switch kind {
            case "项目":
                key = scan.projectPath(for: record.project)
            case "对话":
                key = record.session
            default:
                key = record.model
            }
            var group: UsageGroup
            if let existing = result[key] {
                group = existing
            } else if kind == "项目" || kind == "对话" {
                let path = kind == "项目" ? key : scan.projectPath(for: record.project)
                group = UsageGroup(id: key, name: projectName(path), detail: path)
            } else {
                group = UsageGroup(id: key, name: record.model, detail: "")
            }
            if kind == "对话" { group.latestUsage = max(group.latestUsage ?? record.date, record.date) }
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
        Group {
            if page == .overview {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) { content }.padding(24)
                }
            } else {
                VStack(alignment: .leading, spacing: 18) { content }
                    .padding(24).frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .sheet(item: $selectedSession) { session in
            let interval = range.intervals(now: Date(), customStart: customStart, customEnd: customEnd).current
            let rangeLabel = range == .custom
                ? customStart.formatted(date: .numeric, time: .omitted) + " – " + customEnd.formatted(date: .numeric, time: .omitted)
                : range.rawValue
            UsageSessionDetailView(model: model, title: session.name, range: rangeLabel,
                                   records: records(in: interval).filter { $0.session == session.id })
        }
    }

    private var content: some View {
        // 汇总、图表和比较共用同一截止时刻与筛选，避免临界时刻口径不同。
        let intervals = range.intervals(now: Date(), customStart: customStart, customEnd: customEnd)
        let previous = page == .overview ? intervals.previous : nil
        let records = records(in: intervals.current)
        let tokens = total(records)
        let costs = model.costTotal(records)
        let customRangeLabel = customStart.formatted(date: .numeric, time: .omitted)
            + " – " + customEnd.formatted(date: .numeric, time: .omitted)
        return Group {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    PanelSegmentedPicker(title: "时间范围", options: UsageRange.allCases,
                                         selection: Binding(get: { range }, set: {
                                             range = $0
                                             showsCustomDates = $0 == .custom
                                         }), optionTitle: \.rawValue).frame(maxWidth: 420)
                        .popover(isPresented: $showsCustomDates, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 12) {
                                DatePicker("开始", selection: $customStart, in: ...customEnd, displayedComponents: .date)
                                DatePicker("结束", selection: $customEnd, in: customStart..., displayedComponents: .date)
                                HStack {
                                    Spacer()
                                    Button("完成") { showsCustomDates = false }.keyboardShortcut(.defaultAction)
                                        .buttonStyle(PanelButtonStyle(prominent: true))
                                }
                            }.font(.system(size: 13)).padding(16).frame(width: 280)
                        }
                    Spacer(minLength: 0)
                    PanelSegmentedPicker(title: "统计指标", options: ["Tokens", "费用"],
                                         selection: $metric, optionTitle: \.self).frame(width: 150)
                }
                HStack {
                    Text("本机日志 · 可能含多个账号")
                        .help("包含本机现存日志与已保存历史，不代表当前账号或其他设备的全部用量。")
                    Spacer(minLength: 8)
                    if let updated = model.updatedAt {
                        Text("扫描于 \(updated.formatted(date: .omitted, time: .shortened))").monospacedDigit()
                    }
                }.font(PanelTypography.detail).foregroundStyle(.secondary)
                HStack {
                    Text("API 等价估算，非订阅账单")
                    Spacer(minLength: 8)
                    if range == .custom { Text(customRangeLabel).monospacedDigit() }
                }.font(PanelTypography.detail).foregroundStyle(.secondary)
                if costs.unpricedCount > 0 {
                    Label("\(costs.unpricedCount) 条未定价，金额仅含已定价部分。", systemImage: "exclamationmark.triangle")
                        .help("可在设置的模型定价中补充单价或速度档位。")
                        .font(PanelTypography.detail).foregroundStyle(quotaColor(remaining: 10))
                }
                ForEach(model.scan.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(quotaColor(remaining: 10)).font(PanelTypography.detail)
                }
                if let error = model.scan.historyError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(quotaColor(remaining: 10)).font(PanelTypography.detail)
                }
            }
            if model.updatedAt == nil {
                ProgressView("正在读取本地用量…").frame(maxWidth: .infinity, minHeight: 260)
            } else if records.isEmpty && page != .overview {
                summary(records, tokens: tokens, previous: previous)
                empty("所选范围内没有用量", detail: "使用 Codex 后刷新；这里只统计本机日志中记录的用量。")
            } else if page == .overview {
                summary(records, tokens: tokens, previous: previous)
                if records.isEmpty {
                    empty("所选范围内没有用量", detail: "使用 Codex 后刷新；这里只统计本机日志中记录的用量。")
                } else {
                    let topSessions = Array(groups(records, by: "对话").prefix(5))
                    chart(records, interval: intervals.current)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            composition(tokens).frame(minWidth: 290, maxWidth: .infinity)
                            ranking(topSessions, title: "高消耗对话")
                                .frame(minWidth: 290, maxWidth: .infinity)
                        }
                        VStack(spacing: 18) {
                            composition(tokens).frame(maxWidth: .infinity)
                            ranking(topSessions, title: "高消耗对话")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("用量构成").font(.headline)
                            Spacer()
                            PanelSegmentedPicker(title: "分组", options: ["模型", "项目"],
                                                 selection: $grouping, optionTitle: \.self).frame(width: 210)
                        }.padding(.horizontal, 18)
                        groupTable(groups(records, by: grouping), total: tokens.total, cost: costs)
                    }.padding(.vertical, 18).panelCard()
                }
            } else {
                summary(records, tokens: tokens, previous: previous)
                groupTable(groups(records, by: page.rawValue), total: tokens.total, cost: costs,
                           opensSession: page == .sessions)
                    .padding(.vertical, 8).panelCard()
            }
            if page == .overview, model.updatedAt != nil {
                Divider().padding(.vertical, 4)
                UsageHeatmapView(model: model)
            }
        }
    }

    private func summary(_ records: [UsageRecord], tokens: UsageTokens, previous: DateInterval?) -> some View {
        let previousRecords = previous.map { self.records(in: $0) }
        let previousTokens = previousRecords.map { total($0).total }
        let cost = model.costTotal(records)
        let previousCost = previousRecords.map { model.costTotal($0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                metricCard("总 Tokens", value: formattedTokens(tokens.total),
                    change: previousTokens.map { change(current: Decimal(tokens.total), previous: Decimal($0), money: false) },
                    previous: previousTokens.map { "\($0.formatted()) Tokens" })
                metricCard("API 等价费用", value: records.isEmpty ? "$0.00" : formattedCost(cost),
                    change: previousCost.map {
                        cost.unpricedCount > 0 || $0.unpricedCount > 0 ? "含未定价，暂不比较"
                            : change(current: cost.amount, previous: $0.amount, money: true)
                    }, previous: previousCost.map { $0.pricedCount == 0 && $0.unpricedCount == 0 ? "$0.00" : formattedCost($0) })
            }
            HStack(spacing: 16) {
                Text("\(Set(records.map { $0.session }).count.formatted()) 个对话")
                Text("输入缓存命中率 \(tokens.cacheHitRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")")
                Spacer(minLength: 0)
                if let previous {
                    Text("上期 \(previous.start.formatted(.dateTime.month().day()))–\(previous.end.formatted(.dateTime.month().day()))")
                        .help("与前一个等长时段比较。上期：\(previous.start.formatted(date: .numeric, time: .shortened)) – \(previous.end.formatted(date: .numeric, time: .shortened))")
                }
            }.font(PanelTypography.detail).foregroundStyle(.secondary).monospacedDigit()
        }
    }
    @ViewBuilder
    private func metricCard(_ label: String, value: String, change: String? = nil, previous: String? = nil) -> some View {
        if page == .overview {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.system(size: 25, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let change {
                    Text(change).font(PanelTypography.detail).foregroundStyle(.secondary).monospacedDigit()
                        .help(previous.map { "上期：\($0)" } ?? "")
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14).panelCard()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).foregroundStyle(.secondary)
                Text(value).fontWeight(.semibold).monospacedDigit()
            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
        }
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
                              interval: DateInterval(start: start, end: end), metric: metric)
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
                            Text(group.subtitle).font(PanelTypography.detail).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(metric == "费用" ? formattedCost(group.cost) : formattedTokens(group.tokens.total) + " Tokens")
                            Text(metric == "费用" ? formattedTokens(group.tokens.total) + " Tokens" : formattedCost(group.cost))
                                .font(PanelTypography.detail).foregroundStyle(.secondary)
                        }.monospacedDigit()
                        Image(systemName: "chevron.right").font(PanelTypography.detail).foregroundStyle(.tertiary)
                    }.font(.callout).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help("\(group.name)\n所选范围内最近用量：\(group.subtitle)\n\(group.id)")
            }
        }.padding(18).panelCard()
    }
    private func groupTable(_ groups: [UsageGroup], total: Int, cost: UsageCost, opensSession: Bool = false) -> some View {
        Table(groups) {
            // 长路径不能决定初始列宽；列宽总和需适配最小主窗口。
            TableColumn("名称") { group in
                let name = HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name).fontWeight(.medium).lineLimit(1)
                        if !group.subtitle.isEmpty { Text(group.subtitle).font(PanelTypography.detail).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    if opensSession {
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(PanelTypography.detail).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .help(opensSession ? "\(group.name)\n所选范围内最近用量：\(group.subtitle)\n\(group.id)\n\(group.detail)"
                          : group.detail.isEmpty ? group.name : "\(group.name)\n\(group.detail)")
                if opensSession {
                    Button { selectedSession = group } label: { name }.buttonStyle(.plain)
                        .accessibilityLabel("查看对话 \(group.name)，\(group.subtitle)")
                } else {
                    name
                }
            }.width(min: 130, ideal: 170, max: 260)
            TableColumn("Tokens") { group in
                Text(formattedTokens(group.tokens.total)).frame(maxWidth: .infinity, alignment: .trailing)
                    .help(group.tokens.total.formatted())
            }.width(min: 70, ideal: 80, max: 140)
            TableColumn("API 等价费用") { group in
                Text(formattedCost(group.cost)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
            }.width(min: 100, ideal: 105, max: 180)
            TableColumn(metric == "费用" ? "费用占比" : "Token 占比") { group in
                Text(share(group, tokens: total, cost: cost)).frame(maxWidth: .infinity, alignment: .trailing)
            }.width(min: 60, ideal: 65, max: 100)
            TableColumn("缓存命中率") { group in
                Text(group.tokens.cacheHitRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }.width(min: 80, ideal: 85, max: 110)
        }
        .monospacedDigit().tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity)
        .frame(height: page == .overview ? min(420, CGFloat(groups.count) * 54 + 32) : nil)
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
    private func projectName(_ path: String) -> String {
        // 已知是项目目录，避免 URL 为推断目录类型而在界面线程执行 lstat。
        path.isEmpty ? "未归属项目" : URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
    }
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
        ? "< $0.01" : cost.amount.formatted(.currency(code: "USD").presentation(.narrow).precision(.fractionLength(2)))
    return cost.unpricedCount > 0 ? amount + "（部分）" : amount
}
