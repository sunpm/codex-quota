import SwiftUI
import Charts
import QuotaCore

struct UsageTrendView: View {
    private struct Total {
        let tokens: Int
        let cost: UsageCost
    }
    private let daily: [Date: [QuotaService: Total]]
    @Binding var metric: String
    @State private var hoveredDay: Date?
    @State private var hoverPoint = CGPoint.zero

    @MainActor
    init(model: UsageModel, daily: [Date: [UsageRecord]], metric: Binding<String>) {
        // 汇总随数据更新，鼠标移动只读取汇总结果。
        self.daily = daily.mapValues { records in
            Dictionary(grouping: records, by: \.service).mapValues {
                Total(tokens: $0.reduce(0) { $0 + $1.tokens.total }, cost: model.costTotal($0))
            }
        }
        _metric = metric
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(metric == "费用" ? "每日估算费用" : "每日用量").font(.headline)
                Spacer()
                Picker("统计指标", selection: $metric) {
                    Text("Tokens").tag("Tokens")
                    Text("费用").tag("费用")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            Chart {
                ForEach(daily.keys.sorted(), id: \.self) { day in
                    ForEach([QuotaService.codex, .claude]) { service in
                        if let total = daily[day]?[service], metric != "费用" || total.cost.pricedCount > 0 {
                            let amount = metric == "费用" ? NSDecimalNumber(decimal: total.cost.amount).doubleValue : Double(total.tokens)
                            BarMark(x: .value("日期", day, unit: .day), y: .value(metric == "费用" ? "USD" : "Tokens", amount))
                                .foregroundStyle(by: .value("服务", service.title))
                                .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)) \(service.title)")
                                .accessibilityValue(metric == "费用" ? formattedCost(total.cost) : "\(total.tokens) Tokens")
                        }
                    }
                }
                if let hoveredDay, daily[hoveredDay] != nil {
                    RuleMark(x: .value("日期", hoveredDay, unit: .day))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                        .accessibilityHidden(true)
                }
            }
            .chartForegroundStyleScale(["Codex": Color.blue, "Claude Code": Color.orange])
            .chartYAxis { AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let number = value.as(Double.self) {
                    Text(metric == "费用" ? number.formatted(.currency(code: "USD")) : formattedTokens(Int(number)))
                } }
            } }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    let plot = geometry[proxy.plotAreaFrame]
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                guard plot.contains(point), let date: Date = proxy.value(atX: point.x - plot.minX) else {
                                    hoveredDay = nil
                                    return
                                }
                                let day = Calendar.current.startOfDay(for: date)
                                hoverPoint = point
                                hoveredDay = daily[day] == nil ? nil : day
                            case .ended:
                                hoveredDay = nil
                            }
                        }
                    if let hoveredDay, let entries = daily[hoveredDay] {
                        let width: CGFloat = 269
                        let height: CGFloat = entries.count > 1 ? 116 : 76
                        let x = hoverPoint.x + (hoverPoint.x + width + 12 < geometry.size.width ? width / 2 + 12 : -width / 2 - 12)
                        let y = hoverPoint.y - height / 2 - 12
                        details(day: hoveredDay, entries: entries)
                            .frame(width: 245, alignment: .leading)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
                            .position(x: min(max(x, width / 2), geometry.size.width - width / 2),
                                      y: min(max(y, height / 2), geometry.size.height - height / 2))
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 210)
        }
        .padding(18).panelCard()
        .onChange(of: metric) { _ in hoveredDay = nil }
        .onChange(of: daily.keys.sorted()) { _ in hoveredDay = nil }
    }

    private func details(day: Date, entries: [QuotaService: Total]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day, format: .dateTime.year().month().day()).fontWeight(.semibold)
            ForEach([QuotaService.codex, .claude]) { service in
                if let total = entries[service] {
                    HStack(alignment: .top) {
                        Circle().fill(service == .codex ? Color.blue : .orange).frame(width: 6, height: 6).padding(.top, 4)
                        Text(service.title)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(metric == "费用" ? formattedCost(total.cost) : "\(total.tokens.formatted()) Tokens")
                            Text(metric == "费用" ? "\(total.tokens.formatted()) Tokens" : formattedCost(total.cost))
                                .foregroundStyle(.secondary)
                        }.monospacedDigit()
                    }
                }
            }
        }.font(.caption)
    }
}
