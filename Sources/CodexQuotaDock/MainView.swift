// Adapted from nanvon/cc-bar (MIT), MenuBar/PopoverRootView.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
// Sidebar and section styling reference farion1231/cc-switch (MIT); see THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI
import QuotaCore

struct MainView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject private var cursorUsage: CursorUsageModel
    @ObservedObject private var resetAnnouncements: ResetAnnouncementMonitor
    @StateObject private var navigation: PanelNavigation
    @StateObject private var usage = UsageModel()
    @StateObject private var updates = AppUpdateModel()
    @State private var selectedService: QuotaService?
    @State private var confirmsHistoryClear = false

    init(model: MonitorModel, showsSettings: Bool = false, navigation: PanelNavigation? = nil) {
        self.model = model
        _cursorUsage = ObservedObject(wrappedValue: model.cursorUsage)
        _resetAnnouncements = ObservedObject(wrappedValue: model.resetAnnouncements)
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
                } else if selectedService == .cursor {
                    ScrollView { CursorUsageView(model: cursorUsage, page: navigation.page) }
                } else {
                    ScrollView { UsageView(model: usage, service: selectedService, page: navigation.page) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, idealWidth: 1140, minHeight: 560, idealHeight: 760)
        .alert("开启持久通知", isPresented: $model.showsPersistentNotificationGuide) {
            Button("前往设置") { model.openNotificationSettings() }
            Button("暂不设置", role: .cancel) {}
        } message: {
            Text(persistentNotificationGuide)
        }
        .task {
            guard model.readsLocalUsage else { return }
            // 仅在面板可见时扫描；Cursor 历史另有五分钟刷新间隔。
            while !Task.isCancelled {
                if NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue == "control-panel" }) {
                    await usage.refresh()
                    if selectedService == .cursor, navigation.page == .overview { await cursorUsage.refresh() }
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
            guard model.readsLocalUsage, (event.object as? NSWindow)?.identifier?.rawValue == "control-panel" else { return }
            Task {
                await usage.refresh()
                if selectedService == .cursor, navigation.page == .overview { await cursorUsage.refresh() }
            }
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
            Text("服务").font(PanelTypography.detail).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 8)
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
            if navigation.page == .settings || (service == .cursor && (navigation.page == .sessions || navigation.page == .projects)) {
                navigation.page = .overview
            }
        } label: {
            HStack(spacing: 8) {
                if let service { ServiceTile(service: service) }
                else { Image(systemName: "square.grid.2x2").frame(width: 22, height: 22) }
                Text(service?.title ?? "全部")
                    .fontWeight(selectedService == service && navigation.page != .settings ? .semibold : .regular)
                Spacer(minLength: 0)
            }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 10)
                .background(selectedService == service && navigation.page != .settings ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.accessibilityAddTraits(selectedService == service && navigation.page != .settings ? .isSelected : [])
    }

    private func navigationButton(_ page: PanelPage) -> some View {
        let unavailable = selectedService == .cursor && (page == .sessions || page == .projects)
        return Button { navigation.page = page } label: {
            HStack(spacing: 8) {
                Image(systemName: page.symbol).frame(width: 22, height: 22)
                Text(page.rawValue).fontWeight(navigation.page == page ? .semibold : .regular)
                Spacer(minLength: 0)
            }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).padding(.horizontal, 10)
                .foregroundStyle(unavailable ? .secondary : .primary)
                .background(navigation.page == page ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.disabled(unavailable)
            .help(unavailable ? "Cursor 未提供\(page.rawValue)信息" : page.rawValue)
            .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(navigation.page == .overview ? "用量统计" : navigation.page.rawValue).font(.system(size: 18, weight: .semibold))
            Spacer()
            if navigation.page != .settings && (navigation.page == .quota ? model.refreshing : selectedService == .cursor ? cursorUsage.refreshing : usage.refreshing) {
                ProgressView().controlSize(.small)
            }
            if navigation.page != .settings {
                Button {
                    if navigation.page == .quota { Task { await model.refresh(force: true) } }
                    else if selectedService == .cursor { Task { await cursorUsage.refresh(force: true) } }
                    else { Task { await usage.refresh() } }
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(navigation.page == .quota ? model.refreshing
                              : selectedService == .cursor ? cursorUsage.refreshing || !cursorUsage.enabled : usage.refreshing)
            }
        }.padding(.horizontal, 24).frame(height: 56)
    }

    private var quotaContent: some View {
        let services = model.enabledServices.filter { selectedService == nil || $0 == selectedService }
        return ScrollView {
            VStack(spacing: 16) {
                if services.isEmpty {
                    VStack(spacing: 12) {
                        Text("尚未启用服务，请在设置中开启监测。")
                            .foregroundStyle(.secondary)
                        Button("打开设置") { navigation.page = .settings }
                    }.font(.body).frame(maxWidth: .infinity, minHeight: 240)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)], spacing: 16) {
                    ForEach(services) { service in
                        let snapshot = model.snapshot(service)
                        QuotaServiceBlock(service: service, windows: snapshot.windows, error: snapshot.errorMessage,
                                          lastSuccess: snapshot.lastSuccess, refreshing: snapshot.refreshing)
                            .panelCard()
                    }
                }
                if services.contains(.codex) {
                    ResetAnnouncementView(model: resetAnnouncements).panelCard()
                }
            }.padding(24)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppUpdateView(model: updates)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("在菜单栏显示额度")
                    Spacer()
                    Toggle("在菜单栏显示额度", isOn: Binding(get: { model.showsMenuBar }, set: { model.setShowsMenuBar($0) })).labelsHidden()
                }
                Divider()
                HStack {
                    Text("登录 Mac 时启动")
                    Spacer()
                    Toggle("登录 Mac 时启动", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })).labelsHidden()
                }
                if let error = model.launchError { Text(error).font(PanelTypography.detail).foregroundStyle(quotaColor(remaining: 10)) }
            }.toggleStyle(.switch).controlSize(.small).padding(16).panelCard()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("服务").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Text("监测").frame(width: 46)
                    Text("恢复通知").frame(width: 60)
                    Text("菜单栏").frame(width: 46)
                }.font(PanelTypography.detail).foregroundStyle(.secondary)
                ForEach(QuotaService.allCases) { service in
                    HStack(spacing: 8) {
                        ServiceTile(service: service)
                        Text(service.title)
                        Spacer(minLength: 0)
                        Toggle("监测 \(service.title)", isOn: Binding(get: { model.isEnabled(service) }, set: { model.setEnabled($0, for: service) }))
                            .labelsHidden().frame(width: 46)
                        Toggle("\(service.title) 恢复通知", isOn: Binding(get: { model.notificationsEnabled(for: service) }, set: { model.setNotificationsEnabled($0, for: service) }))
                            .labelsHidden().frame(width: 60).disabled(!model.isEnabled(service))
                        Toggle("在菜单栏显示 \(service.title)", isOn: Binding(get: { model.isShownInMenuBar(service) }, set: { model.setShownInMenuBar($0, for: service) }))
                            .labelsHidden().frame(width: 46).disabled(!model.showsMenuBar || !model.isEnabled(service))
                    }.toggleStyle(.switch).controlSize(.small).padding(.vertical, 3)
                }
                Text("监测开关控制额度查询；用量统计独立读取本机日志。")
                    .font(PanelTypography.detail).foregroundStyle(.secondary)
                HStack {
                    Text("查询间隔")
                    Spacer()
                    Text("30 秒").foregroundStyle(.secondary)
                }.padding(.top, 4)
            }.padding(16).panelCard()
            VStack(alignment: .leading, spacing: 8) {
                Text("恢复通知").font(.headline)
                Text(model.notificationStatus).font(PanelTypography.detail).foregroundStyle(.secondary)
                HStack {
                    if !model.persistentNotificationsEnabled {
                        Button("开启持久通知") { model.showPersistentNotificationGuide() }
                    }
                    Button("测试通知") { Task { await model.sendTestNotification() } }
                    Button("系统设置") { model.openNotificationSettings() }
                }
                if let error = model.notificationError { Text(error).font(PanelTypography.detail).foregroundStyle(.primary) }
                Divider().padding(.vertical, 4)
                HStack {
                    Text("Codex 重置动态通知")
                    Spacer()
                    Toggle("Codex 重置动态通知", isOn: Binding(get: { resetAnnouncements.notificationsEnabled },
                        set: { model.setResetNotificationsEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!model.isEnabled(.codex))
                        .help("提醒 Tibo 的重置预告、确认与发卡消息，个人额度恢复通知仍由实际读数触发。")
                }
            }.padding(16).panelCard()
            usageHistorySettings
            PricingSettingsView(model: usage).padding(16).panelCard()
            Text("Antigravity 需保持运行。首次读取登录态可能需要钥匙串授权。")
                .font(PanelTypography.detail).foregroundStyle(.secondary)
            HStack {
                Text(appName)
                Spacer()
                Link("致谢 cc-bar · MIT", destination: URL(string: "https://github.com/nanvon/cc-bar")!)
            }.font(PanelTypography.detail).foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
    }

    private var usageHistorySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用量历史").font(.headline)
            HStack {
                Button("重新扫描日志") { Task { await usage.refresh(rescan: true) } }
                Spacer()
                Button("清除已保存历史…", role: .destructive) { confirmsHistoryClear = true }
            }.disabled(usage.refreshing || !model.readsLocalUsage)
            if let error = usage.historyActionError ?? usage.scan.historyError {
                Text(error).font(PanelTypography.detail).foregroundStyle(quotaColor(remaining: 10))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                ServiceTile(service: service)
                Text(service.title).font(.headline)
                Spacer(minLength: 0)
                Text("剩余").font(PanelTypography.detail).foregroundStyle(.secondary)
            }
            if windows.isEmpty {
                Text(refreshing ? "正在读取额度…" : "暂无额度读数")
                    .font(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }
            ForEach(windows) { window in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(window.displayLabel).font(.body).lineLimit(2).help(window.displayLabel)
                        Spacer(minLength: 0)
                        Text(window.percentageText)
                            .font(.system(size: 24, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(quotaColor(remaining: window.remaining)).fixedSize()
                    }
                    QuotaProgressBar(remaining: window.remaining, tint: quotaColor(remaining: window.remaining), height: 6)
                        .accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if window.resetsAt != nil {
                                Text(window.compactResetCountdown(at: context.date))
                                    .font(.system(size: 13, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(.primary)
                                    .help("距额度重置")
                            }
                        }
                        Spacer(minLength: 0)
                        if let reset = window.resetsAt {
                            Text("重置 · \(reset.formatted(.dateTime.month().day().hour().minute()))")
                                .monospacedDigit()
                        } else {
                            Text("重置时间未知")
                        }
                    }.font(PanelTypography.detail).foregroundStyle(.secondary)
                }
            }
            if !windows.isEmpty {
                Text(refreshing ? "正在查询…" : lastSuccess.map { "\(error == nil ? "更新于" : "数据已过期 · 更新于") \($0.formatted(date: .omitted, time: .standard))" } ?? "等待首次读取")
                    .font(PanelTypography.detail).foregroundStyle(.secondary).monospacedDigit()
            }
            if let error {
                Label {
                    Text(error).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(quotaColor(remaining: 10))
                }.font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
