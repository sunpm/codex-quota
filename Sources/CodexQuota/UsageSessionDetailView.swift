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
    @AppStorage("usage.columns.speed") private var showsSpeed = true
    @AppStorage("usage.columns.firstToken") private var showsFirstToken = true
    @AppStorage("usage.columns.cacheWrite") private var showsCacheWrite = false
    @AppStorage("usage.columns.billingTier") private var showsBillingTier = false

    var body: some View {
        let tokens = records.reduce(into: UsageTokens()) { $0.add($1.tokens) }
        let cost = model.costTotal(records)
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
                Text("\(formattedTokens(tokens.total)) Tokens").fontWeight(.medium).help(tokens.total.formatted())
                Text(cost.unpricedCount > 0 ? "已定价费用" : "API 等价费用").foregroundStyle(.secondary)
                    .help("API 等价估算；缺少计费档位的旧日志按 Standard 估算。")
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
            if tiers.count > 1 {
                HStack(spacing: 12) {
                    ForEach(UsageSpeedTier.allCases.map(Optional.some) + [nil], id: \.self) { tier in
                        if let rows = tiers[tier] {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(tier?.rawValue ?? "未知档位").font(.headline)
                                Text("\(formattedTokens(rows.reduce(0) { $0 + $1.tokens.total })) Tokens")
                                costLabel(rows).foregroundStyle(.secondary)
                            }.monospacedDigit().frame(maxWidth: .infinity, alignment: .leading).padding(12).panelCard()
                        }
                    }
                }
            }
            UsageRecordTable(model: model, records: records,
                             showsSpeed: showsSpeed, showsFirstToken: showsFirstToken,
                             showsCacheWrite: showsCacheWrite, showsBillingTier: showsBillingTier)
        }
        .padding(20)
        .frame(minWidth: 960, idealWidth: 1000, minHeight: 480, idealHeight: 640)
        .buttonStyle(PanelButtonStyle())
    }

    private func costLabel(_ records: [UsageRecord]) -> some View {
        let cost = model.costTotal(records)
        let exact = cost.pricedCount > 0
            ? "$" + NSDecimalNumber(decimal: cost.amount).stringValue
            : formattedCost(cost)
        return Text(formattedCost(cost)).help(exact + (cost.unpricedCount > 0 ? "\n\(cost.unpricedCount) 条未定价" : ""))
    }
}

// NSTableView 的原生列显隐兼容 macOS 13；SwiftUI Table 的条件列需要 macOS 14.4。
private struct UsageRecordTable: NSViewRepresentable {
    let model: UsageModel
    let records: [UsageRecord]
    let showsSpeed: Bool
    let showsFirstToken: Bool
    let showsCacheWrite: Bool
    let showsBillingTier: Bool

    enum Column: String, CaseIterable {
        case time = "时间", model = "模型", input = "新增输入", output = "输出", cached = "缓存命中"
        case cacheWrite = "缓存写入", cost = "估算费用", speed = "速度", firstToken = "首字", tier = "计费档位"

        var width: CGFloat {
            switch self {
            case .time: return 110
            case .model: return 155
            case .tier: return 120
            case .speed: return 100
            case .cost: return 95
            case .output, .firstToken: return 75
            default: return 85
            }
        }
        var numeric: Bool { self != .time && self != .model && self != .tier }
        var help: String {
            switch self {
            case .speed: return "输出 Token ÷ 日志估算耗时，包含首字等待。仅显示输出至少 200 Token、耗时至少 1 秒的记录。"
            case .firstToken: return "从上一请求边界到首次模型输出的估算时间，可能先输出推理。旧日志或以工具调用开头的响应可能无法推算。"
            case .cached: return "命中缓存的输入 Token 数，不是缓存命中率。"
            case .cacheWrite: return "日志未提供时显示 —，明确报告零才显示 0。"
            case .tier: return "用于费用估算，不代表实际生成速度。缺少档位的旧日志按 Standard 估算。"
            case .cost: return "API 等价估算，非订阅账单。"
            default: return rawValue
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .inset
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 28
        table.intercellSpacing = NSSize(width: 12, height: 2)
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.setAccessibilityLabel("用量明细")
        for kind in Column.allCases {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(kind.rawValue))
            column.title = kind.rawValue
            column.headerToolTip = kind.help
            column.headerCell.alignment = kind.numeric ? .right : .left
            column.width = kind.width
            column.minWidth = kind.width - 15
            column.maxWidth = kind.width + 35
            column.resizingMask = .userResizingMask
            table.addTableColumn(column)
        }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.records = records.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        let table = scroll.documentView as! NSTableView
        for column in table.tableColumns {
            switch Column(rawValue: column.identifier.rawValue)! {
            case .cacheWrite: column.isHidden = !showsCacheWrite
            case .speed: column.isHidden = !showsSpeed
            case .firstToken: column.isHidden = !showsFirstToken
            case .tier: column.isHidden = !showsBillingTier
            default: break
            }
        }
        table.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: UsageRecordTable
        var records: [UsageRecord] = []
        init(_ parent: UsageRecordTable) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { records.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn else { return nil }
            let kind = Column(rawValue: tableColumn.identifier.rawValue)!
            let record = records[row]
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = tableColumn.identifier
                let text = NSTextField(labelWithString: "")
                text.lineBreakMode = .byTruncatingTail
                text.maximumNumberOfLines = 1
                text.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(text)
                cell.textField = text
                NSLayoutConstraint.activate([
                    text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            let tier = record.speedTier.map {
                $0 == .standard && record.serviceTierReported != true ? "Standard（估算）" : $0.rawValue
            } ?? "未知（\(record.serviceTier)）"
            let value: String
            let tip: String
            switch kind {
            case .time:
                value = formattedUsageTime(record.date)
                tip = record.date.formatted(date: .complete, time: .complete)
            case .model:
                value = record.model
                tip = "\(record.model)\n计费档位：\(tier)"
            case .input, .output, .cached, .cacheWrite:
                let count: Int? = kind == .input ? record.tokens.input : kind == .output ? record.tokens.output
                    : kind == .cached ? record.tokens.cached : record.tokens.reportedCacheWrite
                value = count.map(formattedTokens) ?? "—"
                tip = count?.formatted() ?? "日志未提供缓存写入量"
            case .cost:
                let cost = parent.model.costTotal([record])
                value = formattedCost(cost)
                tip = cost.pricedCount > 0 ? "$" + NSDecimalNumber(decimal: cost.amount).stringValue : value
            case .speed:
                value = record.estimatedOutputTokensPerSecond.map {
                    "≈\($0.formatted(.number.precision(.fractionLength($0 >= 1 ? 0 : 1)))) tok/s"
                } ?? "—"
                tip = kind.help
            case .firstToken:
                value = record.estimatedFirstToken.map { "≈\($0.formatted(.number.precision(.fractionLength(1))))s" } ?? "—"
                tip = kind.help
            case .tier:
                value = tier
                tip = "计费档位：\(tier)\n日志值：\(record.serviceTier)"
            }
            let text = cell.textField!
            text.stringValue = value
            text.font = kind == .model ? .monospacedSystemFont(ofSize: 12, weight: .regular)
                : .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            text.alignment = kind.numeric ? .right : .left
            text.textColor = .labelColor
            cell.toolTip = tip
            return cell
        }
    }
}
