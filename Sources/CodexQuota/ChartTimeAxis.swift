import SwiftUI
import Charts

func chartTimeAxis(interval: DateInterval, hourly: Bool, width: CGFloat) -> some AxisContent {
    let unit: Calendar.Component = hourly ? .hour : .day
    let units = Calendar.current.dateComponents([unit], from: interval.start, to: interval.end).value(for: unit) ?? 0
    // 每个标签预留约 80pt；标签始终与对应刻度居中对齐。
    let labelCount = max(2, Int(width / 80))
    let step = max(1, Int(ceil(Double(units) / Double(labelCount - 1))))
    // 两端使用相同的半标签预算；放不下时整组省略，不移动标签或数据。
    let edgeDuration = interval.duration * 40 / max(width, 1)
    return AxisMarks(preset: .aligned, values: .stride(by: unit, count: step)) { value in
        if let date = value.as(Date.self),
           date.timeIntervalSince(interval.start) >= edgeDuration,
           interval.end.timeIntervalSince(date) >= edgeDuration {
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: hourly
                           ? .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                           : .dateTime.month(.twoDigits).day(.twoDigits),
                           centered: false, anchor: .top,
                           collisionResolution: .greedy(minimumSpacing: 8), verticalSpacing: 8)
                .font(PanelTypography.detail.monospacedDigit())
        }
    }
}
