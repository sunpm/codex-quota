import SwiftUI
import QuotaCore

struct CursorUsageView: View {
    @ObservedObject var model: CursorUsageModel
    let page: PanelPage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Cursor · 账号全设备用量").foregroundStyle(.secondary)
                Spacer()
                Link("Dashboard", destination: URL(string: "https://cursor.com/dashboard?tab=usage")!)
            }
            if !model.enabled {
                Text("在设置中开启 Cursor 监测后查看用量。")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else if page != .overview {
                Text("Cursor 未提供可归属的\(page.rawValue)信息，请在概览查看账号用量。")
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                HStack {
                    DatePicker("开始", selection: $model.startDate, in: ...model.endDate, displayedComponents: .date)
                    DatePicker("结束", selection: $model.endDate, in: model.startDate...Date(), displayedComponents: .date)
                }
                if let error = model.errorMessage {
                    Label((model.snapshot == nil ? "" : "数据已过期 · ") + error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if let snapshot = model.snapshot {
                    let totals = CursorUsageTotals(events: snapshot.events)
                    HStack {
                        Text("\(snapshot.interval.start.formatted(date: .numeric, time: .shortened)) – \(snapshot.interval.end.formatted(date: .numeric, time: .shortened))")
                        Spacer()
                        Text("更新于 \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                    }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                        metric("总 Tokens", tokens(totals))
                        metric("请求数", totals.requests.formatted())
                        metric("服务端费用 · USD", cost(totals))
                    }
                    if snapshot.events.isEmpty {
                        Text("接口未返回该范围内的用量。")
                            .frame(maxWidth: .infinity, minHeight: 160).foregroundStyle(.secondary)
                    } else {
                        modelTable(snapshot.events)
                    }
                    if totals.missingTokens > 0 || totals.cost.unpricedCount > 0 {
                        Text("\(totals.missingTokens) 条记录缺少完整 Token，\(totals.cost.unpricedCount) 条记录缺少费用；仅汇总已知值。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text("服务端费用可能包含套餐内用量，不代表额外账单。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if model.refreshing {
                    ProgressView("正在读取 Cursor 用量…").frame(maxWidth: .infinity, minHeight: 240)
                } else if model.errorMessage == nil {
                    Text("暂无 Cursor 用量快照").frame(maxWidth: .infinity, minHeight: 240).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .task(id: model.interval) {
            if page == .overview { await model.refresh() }
        }
        .onChange(of: model.enabled) { enabled in
            if enabled, page == .overview { Task { await model.refresh() } }
        }
        .onChange(of: page) { page in
            if page == .overview { Task { await model.refresh() } }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).panelCard()
    }

    private func modelTable(_ events: [CursorUsageEvent]) -> some View {
        let grouped = Dictionary(grouping: events, by: \.model)
        let totals: [(model: String, totals: CursorUsageTotals)] = grouped.map {
            (model: $0.key, totals: CursorUsageTotals(events: $0.value))
        }
        let groups = totals.sorted {
            $0.totals.tokens == $1.totals.tokens ? $0.model < $1.model : $0.totals.tokens > $1.totals.tokens
        }
        return VStack(spacing: 0) {
            HStack {
                Text("模型"); Spacer()
                Text("Tokens").frame(width: 130, alignment: .trailing)
                Text("请求数").frame(width: 70, alignment: .trailing)
                Text("服务端费用").frame(width: 130, alignment: .trailing)
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            ForEach(groups, id: \.model) { group in
                Divider()
                HStack {
                    Text(group.model).lineLimit(1).help(group.model)
                    Spacer(minLength: 8)
                    Text(tokens(group.totals)).frame(width: 130, alignment: .trailing)
                    Text(group.totals.requests.formatted()).frame(width: 70, alignment: .trailing)
                    Text(cost(group.totals)).frame(width: 130, alignment: .trailing)
                        .help(group.totals.cost.pricedCount == 0 ? "接口未提供费用"
                              : group.totals.cost.amount.formatted(.currency(code: "USD").precision(.fractionLength(2...8))))
                }.font(.callout).monospacedDigit().padding(.vertical, 11)
            }
        }.padding(18).panelCard()
    }

    private func tokens(_ totals: CursorUsageTotals) -> String {
        guard totals.requests == 0 || totals.missingTokens < totals.requests else { return "不可用" }
        return totals.tokens.formatted(.number) + (totals.missingTokens > 0 ? "（部分）" : "")
    }

    private func cost(_ totals: CursorUsageTotals) -> String {
        if totals.requests == 0 { return "$0.00" }
        if totals.cost.pricedCount == 0 { return "不可用" }
        return formattedCost(totals.cost)
    }
}
