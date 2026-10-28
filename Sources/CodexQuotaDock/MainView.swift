// Adapted from nanvon/cc-bar (MIT), MenuBar/PopoverRootView.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
// Sidebar and section styling reference farion1231/cc-switch (MIT); see THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI
import QuotaCore

struct MainView: View {
    @ObservedObject var model: MonitorModel
    @StateObject private var navigation: PanelNavigation
    @StateObject private var usage = UsageModel()
    @State private var selectedService: QuotaService?
    @State private var confirmsHistoryClear = false

    init(model: MonitorModel, showsSettings: Bool = false, navigation: PanelNavigation? = nil) {
        self.model = model
        _navigation = StateObject(wrappedValue: navigation ?? PanelNavigation(page: showsSettings ? .settings : .overview))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if navigation.page == .settings {
                    ScrollView { settings.frame(maxWidth: 760).padding(24).frame(maxWidth: .infinity) }
                } else if navigation.page == .quota {
                    quotaContent
                } else {
                    ScrollView { UsageView(model: usage, service: selectedService, page: navigation.page) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 480, idealWidth: 1140, minHeight: 440, idealHeight: 760)
        .alert("开启持久通知", isPresented: $model.showsPersistentNotificationGuide) {
            Button("前往设置") { model.openNotificationSettings() }
            Button("暂不设置", role: .cancel) {}
        } message: {
            Text(persistentNotificationGuide)
        }
        .task {
            guard model.readsLocalUsage else { return }
            // 只在面板可见时刷新日志，不增加后台网络请求。
            while !Task.isCancelled {
                if NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue == "control-panel" }) {
                    await usage.refresh()
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
            guard model.readsLocalUsage, (event.object as? NSWindow)?.identifier?.rawValue == "control-panel" else { return }
            Task { await usage.refresh() }
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Codex Quota Dock"
    }

    private var persistentNotificationGuide: String {
        let style: String
        if #available(macOS 26, *) {
            style = "开启桌面提醒，并将样式设为“持续”。"
        } else {
            style = "将提醒样式设为“提醒”。"
        }
        return "让额度恢复提醒保留到手动关闭。\n\n在“系统设置 → 通知”中选择“\(appName)”，开启“允许通知”，\(style)"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("服务").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 8)
            serviceButton(nil)
            ForEach(QuotaService.allCases) { service in serviceButton(service) }
            Divider().padding(.vertical, 12)
            ForEach(PanelPage.allCases.filter { $0 != .settings }) { page in
                navigationButton(page)
            }
            Spacer()
            navigationButton(.settings)
        }
        .buttonStyle(.plain).font(.system(size: 13)).padding(12).frame(width: 188)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func serviceButton(_ service: QuotaService?) -> some View {
        Button {
            selectedService = service
            if navigation.page == .settings { navigation.page = .overview }
        } label: {
            HStack(spacing: 8) {
                if let service { ServiceTile(service: service) }
                else { Image(systemName: "square.grid.2x2").frame(width: 22, height: 22) }
                Text(service?.title ?? "全部")
                    .fontWeight(selectedService == service ? .semibold : .regular)
                Spacer(minLength: 0)
            }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 10)
                .background(selectedService == service ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.accessibilityAddTraits(selectedService == service ? .isSelected : [])
    }

    private func navigationButton(_ page: PanelPage) -> some View {
        Button { navigation.page = page } label: {
            HStack(spacing: 8) {
                Image(systemName: page.symbol).frame(width: 22, height: 22)
                Text(page.rawValue).fontWeight(navigation.page == page ? .semibold : .regular)
                Spacer(minLength: 0)
            }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).padding(.horizontal, 10)
                .foregroundStyle(.primary)
                .background(navigation.page == page ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.accessibilityAddTraits(navigation.page == page ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(navigation.page == .overview ? "用量统计" : navigation.page.rawValue).font(.system(size: 18, weight: .semibold))
            Spacer()
            if usage.refreshing && navigation.page != .settings && navigation.page != .quota {
                ProgressView().controlSize(.small)
            }
            if navigation.page != .settings {
                Button {
                    if navigation.page == .quota { Task { await model.refresh(force: true) } }
                    else { Task { await usage.refresh() } }
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(navigation.page == .quota ? model.refreshing : usage.refreshing)
            }
        }.padding(.horizontal, 24).frame(height: 56)
    }

    private var quotaContent: some View {
        let services = model.enabledServices.filter { selectedService == nil || $0 == selectedService }
        return ScrollView {
            VStack(spacing: 14) {
                if services.isEmpty {
                    VStack(spacing: 12) {
                        Text("尚未启用服务，请在设置中开启监测。")
                            .foregroundStyle(.secondary)
                        Button("打开设置") { navigation.page = .settings }
                    }.font(.system(size: 12)).padding(24)
                }
                ForEach(services) { service in
                    let snapshot = model.snapshot(service)
                    QuotaServiceBlock(service: service, windows: snapshot.windows, error: snapshot.errorMessage,
                                      lastSuccess: snapshot.lastSuccess, refreshing: snapshot.refreshing)
                        .panelCard()
                }
            }.padding(24)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("在菜单栏显示额度", isOn: Binding(get: { model.showsMenuBar }, set: { model.setShowsMenuBar($0) }))
                Divider()
                Toggle("登录 Mac 时启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if let error = model.launchError { Text(error).font(.caption).foregroundStyle(.orange) }
            }.toggleStyle(.switch).controlSize(.small).padding(16).panelCard()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("服务")
                    Spacer()
                    Text("监测").frame(width: 46)
                    Text("重置通知").frame(width: 60)
                    Text("菜单栏").frame(width: 46)
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
                        Toggle("在菜单栏显示 \(service.title)", isOn: Binding(get: { model.isShownInMenuBar(service) }, set: { model.setShownInMenuBar($0, for: service) }))
                            .labelsHidden().frame(width: 46).disabled(!model.showsMenuBar || !model.isEnabled(service))
                    }.toggleStyle(.switch).controlSize(.small)
                }
                Text("监测开关控制额度查询；用量统计独立读取本机日志。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Text("查询间隔")
                    Spacer()
                    Text("30 秒").foregroundStyle(.secondary)
                }.padding(.top, 4)
            }.padding(16).panelCard()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("恢复通知")
                    Spacer()
                    if !model.persistentNotificationsEnabled {
                        Button("开启持久通知") { model.showPersistentNotificationGuide() }.controlSize(.small)
                    }
                    Button("测试通知") { Task { await model.sendTestNotification() } }.controlSize(.small)
                    Button("系统设置") { model.openNotificationSettings() }.controlSize(.small)
                }
                Text(model.notificationStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                if let error = model.notificationError { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            }.padding(16).panelCard()
            usageHistorySettings
            PricingSettingsView(model: usage).padding(16).panelCard()
            Text("Antigravity 需保持运行。首次读取登录态可能需要钥匙串授权。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Text("\(appName) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                Spacer()
                Link("致谢 cc-bar · MIT", destination: URL(string: "https://github.com/nanvon/cc-bar")!)
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .font(.system(size: 13))
    }

    private var usageHistorySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用量历史")
            HStack {
                Button("重新扫描日志") { Task { await usage.refresh(rescan: true) } }
                Spacer()
                Button("清除已保存历史…", role: .destructive) { confirmsHistoryClear = true }
            }.controlSize(.small).disabled(usage.refreshing || !model.readsLocalUsage)
            if let error = usage.historyActionError ?? usage.scan.historyError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }.padding(16).panelCard()
            .alert("清除已保存的用量历史？", isPresented: $confirmsHistoryClear) {
                Button("取消", role: .cancel) {}
                Button("清除并重新扫描", role: .destructive) { Task { await usage.clearHistory() } }
            } message: {
                Text("仅清除本应用保存的全部服务用量历史，随后重新扫描现存日志。已删除源日志对应的历史将无法恢复；源日志与模型定价不会被删除。")
            }
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
