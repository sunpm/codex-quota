import SwiftUI
import QuotaCore

struct MainView: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 28)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex 额度").font(.title2.bold())
                    Text("每 30 秒自动刷新").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.refreshing { ProgressView().controlSize(.small) }
                Button { Task { await model.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.refreshing).help("立即刷新")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.selectedWindow?.percentageText ?? "—")
                        .font(.system(size: 68, weight: .semibold, design: .rounded)).monospacedDigit()
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("剩余额度").font(.headline)
                        Text(model.selectedWindow?.periodText ?? "正在连接 Codex")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: model.selectedWindow?.remaining ?? 0, total: 100).tint(.teal)
                if let reset = model.selectedWindow?.resetsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack {
                            Text(reset, format: .dateTime.month().day().hour().minute())
                            Text("重置").foregroundStyle(.secondary)
                            Spacer()
                            Text(countdown(to: reset, from: context.date)).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                }
            }
            .padding(20).background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

            if model.windows.count > 1 {
                Picker("Dock 显示", selection: $model.selectedWindowID) {
                    Text("自动选择 Codex 最低剩余额度").tag("")
                    ForEach(model.windows) { window in
                        Text("\(window.name) · \(window.periodText) · \(window.percentageText)").tag(window.id)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(model.errorMessage == nil && model.lastSuccess != nil ? Color.teal : Color.orange).frame(width: 7, height: 7)
                    if let date = model.lastSuccess {
                        Text("最近更新 \(date.formatted(date: .omitted, time: .standard))")
                    } else { Text("等待首次读取") }
                    Spacer()
                    Text(model.errorMessage == nil ? "自动监听中" : "数据可能已过期")
                }.font(.caption).foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: model.notificationsEnabled ? "bell.badge" : "bell.slash").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("恢复提醒").font(.headline)
                        Text(model.notificationStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.notificationsEnabled {
                        Button("测试通知") { Task { await model.sendTestNotification() } }
                    } else {
                        Button("通知设置") { model.openNotificationSettings() }
                    }
                }
                if let error = model.notificationError { Text(error).font(.caption).foregroundStyle(.orange) }
                Toggle("登录 Mac 时启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch).controlSize(.small)
                if let error = model.launchError { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Text("拖动悬浮面板可调整位置。关闭本窗口后继续监听。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(26).frame(width: 470)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func countdown(to end: Date, from now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now)))
        guard seconds > 0 else { return "等待服务端更新" }
        let days = seconds / 86400
        let hours = seconds / 3600 % 24
        let minutes = seconds / 60 % 60
        if days > 0 { return "还剩 \(days) 天 \(hours) 小时" }
        if hours > 0 { return "还剩 \(hours) 小时 \(minutes) 分钟" }
        return "还剩 \(minutes) 分 \(seconds % 60) 秒"
    }
}
