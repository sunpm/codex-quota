// Detail fields reference farion1231/cc-switch (MIT), RequestDetailPanel.tsx.
// See THIRD_PARTY_NOTICES.md and Resources/ThirdPartyNotices/cc-switch-LICENSE.txt.
import SwiftUI
import QuotaCore

struct UsageSessionDetailView: View {
    @ObservedObject var model: UsageModel
    let title: String
    let range: String
    let records: [UsageRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let tokens = records.reduce(into: UsageTokens()) { $0.add($1.tokens) }
        let tiers = Dictionary(grouping: records, by: \.speedTier)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
                    .buttonStyle(PanelButtonStyle(prominent: true))
            }
            HStack {
                Text("\(range) · \(records.count.formatted()) 条用量记录").foregroundStyle(.secondary)
                Spacer()
                Text("\(tokens.total.formatted()) Tokens").fontWeight(.medium)
                costLabel(records)
            }.monospacedDigit()
            if let record = records.first {
                Text(record.session).font(PanelTypography.detail).foregroundStyle(.secondary).textSelection(.enabled)
            }
            let directories = Set(records.map(\.project)).filter { !$0.isEmpty }.sorted()
            if !directories.isEmpty {
                DisclosureGroup("工作目录") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(directories, id: \.self) { directory in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(directory).textSelection(.enabled)
                                let project = model.scan.projectPath(for: directory)
                                if project != directory {
                                    Text("主项目：\(project)").foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.font(PanelTypography.detail).padding(.top, 4)
                }
            }
            HStack(spacing: 12) {
                ForEach(UsageSpeedTier.allCases.map(Optional.some) + [nil], id: \.self) { tier in
                    if let rows = tiers[tier] {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tier?.rawValue ?? "未知档位").font(.headline)
                            Text("\(rows.reduce(0) { $0 + $1.tokens.total }.formatted()) Tokens")
                            costLabel(rows).foregroundStyle(.secondary)
                        }.monospacedDigit().frame(maxWidth: .infinity, alignment: .leading).padding(12).panelCard()
                    }
                }
            }
            Table(records.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }) {
                TableColumn("时间") { record in
                    Text(record.date, format: .dateTime.month().day().hour().minute().second())
                        .help(record.date.formatted(date: .complete, time: .complete))
                }.width(min: 120, ideal: 130)
                TableColumn("模型") { record in
                    Text(record.model).lineLimit(1).help(record.model)
                }.width(min: 120, ideal: 160)
                TableColumn("新增输入") { number($0.tokens.input) }.width(min: 70, ideal: 85)
                TableColumn("输出") { number($0.tokens.output) }.width(min: 60, ideal: 75)
                TableColumn("缓存读取") { number($0.tokens.cached) }.width(min: 70, ideal: 85)
                TableColumn("缓存写入") { number($0.tokens.cacheWrite) }.width(min: 70, ideal: 85)
                TableColumn("速度档位") { record in
                    Text(record.speedTier?.rawValue ?? "未知（\(record.serviceTier)）")
                        .lineLimit(1).help("日志档位：\(record.serviceTier)")
                }.width(min: 75, ideal: 85)
                TableColumn("估算费用") { record in
                    costLabel([record]).frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 100, ideal: 115)
            }.monospacedDigit()
            Text("API 等价估算 · 缺少速度档位的旧日志按 Standard 估算")
                .font(PanelTypography.detail).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 800, idealWidth: 1000, minHeight: 480, idealHeight: 640)
        .buttonStyle(PanelButtonStyle())
    }

    private func number(_ value: Int) -> some View {
        Text(value.formatted()).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func costLabel(_ records: [UsageRecord]) -> some View {
        let cost = model.costTotal(records)
        let exact = cost.pricedCount > 0
            ? "$" + NSDecimalNumber(decimal: cost.amount).stringValue + (cost.unpricedCount > 0 ? "（部分）" : "")
            : formattedCost(cost)
        return Text(formattedCost(cost)).help(exact)
    }
}
