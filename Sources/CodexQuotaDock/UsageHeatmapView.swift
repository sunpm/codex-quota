// Calendar layout references farion1231/cc-switch (MIT); see THIRD_PARTY_NOTICES.md.
import SwiftUI
import QuotaCore

struct UsageHeatmapView: View {
    @ObservedObject var model: UsageModel
    @State private var metric = "Tokens"

    private struct Day: Identifiable {
        let id: Date
        var tokens = 0
        var cost = UsageCost()
    }

    var body: some View {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        // 周一至周日排列，包含本周及前 52 周；日期运算遵循本地时区和夏令时。
        let weekday = (calendar.component(.weekday, from: today) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -364 - weekday, to: today)!
        let days = dailyUsage(start: start, now: now, calendar: calendar)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("用量热力图").font(.headline)
                Text("最近 53 周").font(PanelTypography.detail).foregroundStyle(.secondary)
                Spacer()
                Picker("热力图指标", selection: $metric) {
                    Text("Tokens").tag("Tokens")
                    Text("费用").tag("费用")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            }
            CalendarGrid(days: days, metric: metric, today: today)
        }.padding(18).panelCard()
    }

    private func dailyUsage(start: Date, now: Date, calendar: Calendar) -> [Day] {
        var totals: [Date: Day] = [:]
        for record in model.scan.records where record.date >= start && record.date <= now {
            let date = calendar.startOfDay(for: record.date)
            var day = totals[date] ?? Day(id: date)
            day.tokens += record.tokens.total
            day.cost.add(model.cost(record))
            totals[date] = day
        }
        return (0..<371).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return totals[date] ?? Day(id: date)
        }
    }

    // 将悬停状态留在日历内，移动鼠标时不重新聚合全部日志。
    private struct CalendarGrid: View {
        let days: [Day]
        let metric: String
        let today: Date
        @State private var hoveredDate: Date?
        @State private var hoveredFrame = CGRect.zero

        var body: some View {
            let calendar = Calendar.current
            let maximum = days.map { value($0) }.max() ?? 0
            let hasUnpriced = days.contains { $0.cost.unpricedCount > 0 }
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { geometry in
                    let size = max(12, min(16, (geometry.size.width - 56 - 52 * 3) / 53))
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(spacing: 3) {
                                ForEach(0..<7) { row in
                                    Text(["一", "", "三", "", "五", "", "日"][row])
                                        .frame(width: 28, height: size)
                                }
                            }.padding(.top, 22).foregroundStyle(.secondary).accessibilityHidden(true)
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 4) {
                                    ZStack(alignment: .topLeading) {
                                        Color.clear.frame(width: 53 * (size + 3) - 3, height: 18)
                                        ForEach(0..<53) { week in
                                            let day = days[week * 7].id
                                            if calendar.component(.day, from: day) <= 7 {
                                                Text(day, format: .dateTime.month(.abbreviated))
                                                    .fixedSize()
                                                    .offset(x: CGFloat(week) * (size + 3))
                                            }
                                        }
                                    }.foregroundStyle(.secondary).accessibilityHidden(true)
                                    HStack(alignment: .top, spacing: 3) {
                                        ForEach(0..<53) { week in
                                            VStack(spacing: 3) {
                                                ForEach(0..<7) { row in
                                                    let day = days[week * 7 + row]
                                                    if day.id <= today {
                                                        GeometryReader { cellGeometry in
                                                            cell(day, maximum: maximum)
                                                                .contentShape(Rectangle())
                                                                .onHover { inside in
                                                                    hoveredDate = inside ? day.id : nil
                                                                    if inside { hoveredFrame = cellGeometry.frame(in: .named("usageHeatmap")) }
                                                                }
                                                        }.frame(width: size, height: size)
                                                    } else {
                                                        Color.clear.frame(width: size, height: size).accessibilityHidden(true)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }.padding(.trailing, 20)
                            }
                        }.font(PanelTypography.detail)
                        if let day = days.first(where: { $0.id == hoveredDate }) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(day.id, format: .dateTime.year().month().day()).fontWeight(.semibold)
                                Text("\(day.tokens.formatted()) Tokens")
                                Text("估算费用：\(formattedCost(day.cost))")
                            }
                            .font(PanelTypography.detail).monospacedDigit()
                            .frame(width: 240, alignment: .leading).padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
                            .position(x: min(max(hoveredFrame.midX, 132), geometry.size.width - 132),
                                      y: hoveredFrame.midY < geometry.size.height / 2 ? hoveredFrame.maxY + 48 : hoveredFrame.minY - 48)
                            .allowsHitTesting(false)
                        }
                    }
                    .coordinateSpace(name: "usageHeatmap")
                }.frame(height: 166)
                HStack(spacing: 5) {
                    if metric == "费用" && hasUnpriced {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [2]))
                            .frame(width: 11, height: 11)
                        Text("含未定价")
                    }
                    Spacer()
                    Text("少")
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 2).fill(color(level: level)).frame(width: 11, height: 11)
                    }
                    Text("多")
                }.font(PanelTypography.detail).foregroundStyle(.secondary).accessibilityElement(children: .combine)
            }
            .onChange(of: metric) { _ in hoveredDate = nil }
        }

        private func value(_ day: Day) -> Double {
            metric == "费用" ? NSDecimalNumber(decimal: day.cost.amount).doubleValue : Double(day.tokens)
        }

        private func cell(_ day: Day, maximum: Double) -> some View {
            let amount = value(day)
            let level = amount > 0 && maximum > 0 ? min(4, max(1, Int(ceil(amount / maximum * 4)))) : 0
            let unpriced = metric == "费用" && day.cost.unpricedCount > 0
            let label = "\(day.id.formatted(date: .complete, time: .omitted))\n\(day.tokens.formatted()) Tokens\n估算费用：\(formattedCost(day.cost))"
            return RoundedRectangle(cornerRadius: 2)
                .fill(color(level: level))
                .overlay {
                    if hoveredDate == day.id {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(.primary.opacity(0.7))
                    }
                    if unpriced {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [2]))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
        }

        private func color(level: Int) -> Color {
            level == 0 ? Color.secondary.opacity(0.10) : Color.teal.opacity([0, 0.25, 0.45, 0.70, 1][level])
        }
    }
}
