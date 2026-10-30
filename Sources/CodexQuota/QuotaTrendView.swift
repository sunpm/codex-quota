import SwiftUI
import Charts
import QuotaCore

struct QuotaTrendView: View {
    let history: QuotaHistory
    let windows: [QuotaWindow]
    @State private var range = "24 小时"

    var body: some View {
        let end = Date()
        let start = end.addingTimeInterval(range == "7 天" ? -7 * 86400 : -86400)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("额度消耗趋势").font(.headline)
                    .help("已用百分比，每五分钟保留最新实测值。重置和采样中断处断开，不补造历史。")
                Spacer()
                PanelSegmentedPicker(title: "趋势范围", options: ["24 小时", "7 天"],
                                     selection: $range, optionTitle: \.self).frame(width: 160)
            }
            if windows.isEmpty {
                Text("成功读取额度后开始记录趋势")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(windows) { window in
                    QuotaWindowTrend(window: window,
                                     points: (history.series[window.id]?.points ?? []).filter { $0.date >= start && $0.date <= end },
                                     interval: DateInterval(start: start, end: end), daily: range == "7 天")
                }
            }
        }.padding(16).panelCard()
    }
}

private struct QuotaWindowTrend: View {
    let window: QuotaWindow
    let points: [QuotaHistory.Point]
    let interval: DateInterval
    let daily: Bool
    @State private var hover: (date: Date, point: QuotaHistory.Point?)?

    var body: some View {
        let tint = quotaColor(remaining: window.remaining)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.displayLabel).font(.callout)
                Spacer()
                if let hover {
                    Text(hover.point?.date ?? hover.date, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
                if let point = hover == nil ? points.last : hover?.point {
                    Text("已用 \(point.usedPercent.formatted(.number.precision(.fractionLength(0...1))))%")
                } else if hover != nil {
                    Text("无采样").foregroundStyle(.secondary)
                }
            }.font(PanelTypography.detail).monospacedDigit()
            GeometryReader { chartGeometry in
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("时间", point.date), y: .value("已用百分比", point.usedPercent),
                                 series: .value("连续观测", point.segment))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(tint)
                        PointMark(x: .value("时间", point.date), y: .value("已用百分比", point.usedPercent))
                            .symbolSize(8)
                            .foregroundStyle(tint)
                            .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .shortened))
                            .accessibilityValue("已用 \(point.usedPercent.formatted())%")
                    }
                    if let hover {
                        RuleMark(x: .value("时间", hover.point?.date ?? hover.date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                            .accessibilityHidden(true)
                    }
                }
                .chartXScale(domain: interval.start...interval.end)
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    chartTimeAxis(interval: interval, hourly: !daily, width: chartGeometry.size.width)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let percent = value.as(Int.self) { Text("\(percent)%").monospacedDigit() }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let plot = geometry[proxy.plotAreaFrame]
                                    guard plot.contains(location),
                                          let date: Date = proxy.value(atX: location.x - plot.minX) else {
                                        hover = nil
                                        return
                                    }
                                    let closest = points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                                    // 只吸附附近的实测点，空白时间不能显示成有读数。
                                    let point: QuotaHistory.Point? = closest.flatMap { point in
                                        guard let x = proxy.position(forX: point.date),
                                              abs(x - (location.x - plot.minX)) <= 12 else { return nil }
                                        return point
                                    }
                                    hover = (date, point)
                                case .ended: hover = nil
                                }
                            }
                    }
                }
            }.frame(height: 120)
        }
        .onChange(of: interval) { _ in hover = nil }
    }
}
