// Adapted from nanvon/cc-bar (MIT), MenuBar/PopoverRootView.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import AppKit
import SwiftUI
import QuotaCore

struct MainView: View {
    @ObservedObject var model: MonitorModel
    @State private var showsSettings = false

    init(model: MonitorModel, showsSettings: Bool = false) {
        self.model = model
        _showsSettings = State(initialValue: showsSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $showsSettings) {
                VStack(spacing: 0) {
                    quotaContent
                    Divider()
                    HStack {
                        Text("每 \(Int(MonitorModel.refreshInterval)) 秒查询")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { showsSettings = true } label: {
                            Label(model.notificationsEnabled ? "\(model.notificationServiceCount) 个服务提醒" : "通知未开启",
                                  systemImage: model.notificationsEnabled && model.notificationServiceCount > 0 ? "bell" : "bell.slash")
                        }.help("打开通知设置")
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .tabItem { Text("用量") }.tag(false)
                ScrollView { settings }
                    .tabItem { Text("设置") }.tag(true)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 440, idealHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("控制面板").font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(refreshSubtitle(at: context.date))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .monospacedDigit().lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Circle()
                .fill(model.errorMessage != nil ? Color.orange : model.lastSuccess != nil ? Color.green : Color.gray)
                .frame(width: 7, height: 7).padding(.trailing, 4)
                .help(model.errorMessage ?? "每 30 秒自动查询")
            Button { Task { await model.refresh(force: true) } } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            Button("退出") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(16)
    }

    private var quotaContent: some View {
        let services = model.enabledServices
        return ScrollView {
            VStack(spacing: 0) {
                if services.isEmpty {
                    VStack(spacing: 12) {
                        Text("尚未启用服务，请在设置中开启监测。")
                            .foregroundStyle(.secondary)
                        Button("打开设置") { showsSettings = true }
                    }.font(.system(size: 12)).padding(24)
                }
                ForEach(Array(services.enumerated()), id: \.element) { index, service in
                    if index > 0 { Divider().padding(.horizontal, 16) }
                    let snapshot = model.snapshot(service)
                    QuotaServiceBlock(service: service, windows: snapshot.windows, error: snapshot.errorMessage,
                                      lastSuccess: snapshot.lastSuccess, refreshing: snapshot.refreshing)
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("查询间隔")
                Spacer()
                Text("30 秒").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("服务")
                    Spacer()
                    Text("监测").frame(width: 46)
                    Text("重置通知").frame(width: 60)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(QuotaService.allCases) { service in
                    HStack(spacing: 8) {
                        ServiceTile(service: service)
                        Text(service.title)
                        Spacer(minLength: 0)
                        Toggle("监测 \(service.title)", isOn: Binding(get: { model.isEnabled(service) }, set: { model.setEnabled($0, for: service) }))
                            .labelsHidden().frame(width: 46)
                        Toggle("\(service.title) 重置通知", isOn: Binding(get: { model.notificationsEnabled(for: service) }, set: { model.setNotificationsEnabled($0, for: service) }))
                            .labelsHidden().frame(width: 60).disabled(!model.isEnabled(service))
                    }.toggleStyle(.switch).controlSize(.small)
                }
                Text("关闭通知仍会查询额度，不会补发关闭期间的恢复事件。关闭监测则停止该服务查询。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("恢复通知")
                    Spacer()
                    Button("测试通知") { Task { await model.sendTestNotification() } }.controlSize(.small)
                    Button("系统设置") { model.openNotificationSettings() }.controlSize(.small)
                }
                Text(model.notificationStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                if let error = model.notificationError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            }
            Toggle("登录 Mac 时启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).controlSize(.small)
            if let error = model.launchError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            Divider()
            Text("复用本机已登录账号，首次读取可能需要钥匙串授权。Antigravity 需保持运行。睡眠时暂停，唤醒后查询；真实额度恢复到 100% 时提醒一次。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Text("Codex 额度 0.4.0")
                Spacer()
                Link("致谢 cc-bar · MIT", destination: URL(string: "https://github.com/nanvon/cc-bar")!)
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
        .padding(16)
    }

    private func refreshSubtitle(at now: Date) -> String {
        if model.enabledServices.isEmpty { return "监测已关闭" }
        if model.refreshing { return "正在刷新…" }
        guard let date = model.lastSuccess else { return model.errorMessage == nil ? "等待数据" : "刷新失败" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let age = seconds < 60 ? "\(seconds) 秒" : seconds < 3600 ? "\(seconds / 60) 分钟" : "\(seconds / 3600) 小时"
        return model.errorMessage == nil ? "\(age)前已刷新" : "部分服务连接失败"
    }
}

private struct QuotaServiceBlock: View {
    let service: QuotaService
    let windows: [QuotaWindow]
    let error: String?
    let lastSuccess: Date?
    let refreshing: Bool

    private var primary: QuotaWindow? { windows.first }
    private var color: Color { quotaColor(remaining: primary?.remaining) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                ServiceTile(service: service)
                Text(service.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                Text(service.vendor).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("剩余额度").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(primary.map { String(Int($0.remaining.rounded(.down))) } ?? "--")
                            .font(.system(size: 32, weight: .semibold)).monospacedDigit().kerning(-0.8)
                        if primary != nil { Text("%").font(.system(size: 16, weight: .semibold)).opacity(0.75) }
                    }.foregroundStyle(color).fixedSize()
                    Text(primary?.displayLabel ?? "当前额度")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .lineLimit(2).help(primary?.displayLabel ?? "当前额度")
                }.frame(width: 72)
                VStack(alignment: .leading, spacing: 8) {
                    QuotaProgressBar(remaining: primary?.remaining ?? 0, tint: color)
                    VStack(alignment: .leading, spacing: 1) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(primary?.compactResetCountdown(at: context.date) ?? "--:--:--")
                                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        }
                        if let reset = primary?.resetsAt {
                            Text("重置 · \(reset.formatted(.dateTime.month().day().hour().minute()))")
                                .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
                        } else {
                            Text("重置时间未知").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(windows.dropFirst())) { window in
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(window.displayLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                            .lineLimit(1).help(window.displayLabel)
                        Spacer(minLength: 2)
                        Text(window.percentageText).font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit().foregroundStyle(quotaColor(remaining: window.remaining))
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(window.compactResetCountdown(at: context.date))
                                .font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary)
                        }.frame(width: 88, alignment: .trailing)
                    }
                    QuotaProgressBar(remaining: window.remaining, tint: quotaColor(remaining: window.remaining), height: 2.5)
                }
            }
            Text(refreshing ? "正在查询…" : lastSuccess.map { "\(error == nil ? "最近更新" : "旧数据") · \($0.formatted(date: .omitted, time: .standard))" } ?? "等待首次读取")
                .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .lineLimit(2).help(error)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
