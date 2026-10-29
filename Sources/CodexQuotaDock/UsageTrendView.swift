import SwiftUI
import Charts
import QuotaCore

struct UsageTrendView: View {
    private struct Total {
        let tokens: Int
        let cost: UsageCost
    }
    private let buckets: [Date: Total]
    let hourly: Bool
    let interval: DateInterval
    private var unit: Calendar.Component { hourly ? .hour : .day }
    let metric: String
    @State private var hoveredBucket: Date?
    @State private var hoverPoint = CGPoint.zero

    @MainActor
    init(model: UsageModel, buckets: [Date: [UsageRecord]], hourly: Bool, interval: DateInterval, metric: String) {
        // 汇总随数据更新，鼠标移动只读取汇总结果。
        self.buckets = buckets.mapValues { records in
            Total(tokens: records.reduce(0) { $0 + $1.tokens.total }, cost: model.costTotal(records))
        }
        self.hourly = hourly
        self.interval = interval
        self.metric = metric
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text((hourly ? "每小时" : "每日") + (metric == "费用" ? "估算费用" : "用量")).font(.headline)
            Chart {
                ForEach(buckets.keys.sorted(), id: \.self) { bucket in
                    if let total = buckets[bucket], metric != "费用" || total.cost.pricedCount > 0 {
                        let amount = metric == "费用" ? NSDecimalNumber(decimal: total.cost.amount).doubleValue : Double(total.tokens)
                        BarMark(x: .value("时间", bucket, unit: unit), y: .value(metric == "费用" ? "USD" : "Tokens", amount))
                            .foregroundStyle(Color.blue)
                            .accessibilityLabel(bucket.formatted(date: .abbreviated, time: hourly ? .shortened : .omitted))
                            .accessibilityValue(metric == "费用" ? formattedCost(total.cost) : "\(total.tokens) Tokens")
                    }
                }
                if let hoveredBucket, buckets[hoveredBucket] != nil {
                    RuleMark(x: .value("时间", hoveredBucket, unit: unit))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                        .accessibilityHidden(true)
                }
            }
            .chartXScale(domain: interval.start...interval.end)
            .chartXAxis {
                AxisMarks(values: hourly ? .stride(by: .hour, count: 3) : .automatic(desiredCount: 6)) { _ in
                    AxisGridLine()
                    AxisTick()
                    if hourly { AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) }
                    else { AxisValueLabel() }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let number = value.as(Double.self) {
                    Text(metric == "费用" ? number.formatted(.currency(code: "USD").presentation(.narrow)) : formattedTokens(Int(number)))
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
                                    hoveredBucket = nil
                                    return
                                }
                                let bucket = Calendar.current.dateInterval(of: unit, for: date)!.start
                                hoverPoint = point
                                hoveredBucket = buckets[bucket] == nil ? nil : bucket
                            case .ended:
                                hoveredBucket = nil
                            }
                        }
                    if let hoveredBucket, let total = buckets[hoveredBucket] {
                        let width: CGFloat = 269
                        let height: CGFloat = 92
                        let x = hoverPoint.x + (hoverPoint.x + width + 12 < geometry.size.width ? width / 2 + 12 : -width / 2 - 12)
                        let y = hoverPoint.y - height / 2 - 12
                        details(bucket: hoveredBucket, total: total)
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
        .onChange(of: metric) { _ in hoveredBucket = nil }
        .onChange(of: buckets.keys.sorted()) { _ in hoveredBucket = nil }
        .onChange(of: interval) { _ in hoveredBucket = nil }
        .onChange(of: hourly) { _ in hoveredBucket = nil }
    }

    private func details(bucket: Date, total: Total) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bucket, format: hourly ? .dateTime.year().month().day().hour().minute() : .dateTime.year().month().day())
                .fontWeight(.semibold)
            HStack {
                Text("Tokens")
                Spacer()
                Text(total.tokens.formatted()).monospacedDigit()
            }
            HStack {
                Text("估算费用")
                Spacer()
                Text(formattedCost(total.cost)).monospacedDigit()
            }
        }.font(PanelTypography.detail)
    }
}
