// Adapted from nanvon/cc-bar (MIT), MenuBar/PopoverRootView.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
// Sidebar and section styling reference farion1231/cc-switch (MIT); see THIRD_PARTY_NOTICES.md.
import AppKit
import SwiftUI
import QuotaCore

struct MainView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject private var resetAnnouncements: ResetAnnouncementMonitor
    @StateObject private var navigation: PanelNavigation
    @StateObject private var usage = UsageModel()
    @ObservedObject private var updates: AppUpdateModel
    @State private var confirmsHistoryClear = false
    @State private var refreshIntervalInput: String
    @State private var showsRefreshIntervalEditor = false
    @FocusState private var refreshIntervalFocused: Bool
    @Namespace private var navigationSelection

    init(model: MonitorModel, showsSettings: Bool = false, navigation: PanelNavigation? = nil) {
        self.model = model
        _resetAnnouncements = ObservedObject(wrappedValue: model.resetAnnouncements)
        _updates = ObservedObject(wrappedValue: model.updates)
        _refreshIntervalInput = State(initialValue: String(model.refreshInterval))
        _navigation = StateObject(wrappedValue: navigation ?? PanelNavigation(page: showsSettings ? .settings : .overview))
    }

    var body: some View {
        HStack(spacing: 0) {
            if #available(macOS 26, *) {
                sidebar.glassEffect(in: RoundedRectangle(cornerRadius: 16)).padding(8)
            } else {
                sidebar.background(Color(nsColor: .windowBackgroundColor))
                Divider()
            }
            VStack(spacing: 0) {
                header
                Divider()
                if navigation.page == .settings {
                    ScrollView { settings.frame(maxWidth: 760).padding(24).frame(maxWidth: .infinity) }
                } else if navigation.page == .quota {
                    quotaContent
                } else {
                    UsageView(model: usage, page: navigation.page)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, idealWidth: 1140, minHeight: 560, idealHeight: 760)
        .contentShape(Rectangle())
        .onTapGesture {
            if showsRefreshIntervalEditor { commitRefreshInterval() }
        }
        .buttonStyle(PanelButtonStyle())
        .sheet(isPresented: $updates.showsInstalledReleaseNotes) {
            InstalledReleaseNotesView(version: updates.currentVersion, markdown: updates.installedReleaseNotes)
                .onAppear { updates.markInstalledReleaseNotesShown() }
        }
        .alert("开启持久通知", isPresented: $model.showsPersistentNotificationGuide) {
            Button("前往设置") { model.openNotificationSettings() }
            Button("暂不设置", role: .cancel) {}
        } message: {
            Text(persistentNotificationGuide)
        }
        .task {
            guard model.readsLocalUsage else { return }
            // 仅在面板可见时扫描本机日志。
            while !Task.isCancelled {
                if NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue == "control-panel" }) {
                    await usage.refresh()
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { event in
            guard model.readsLocalUsage, (event.object as? NSWindow)?.identifier?.rawValue == "control-panel" else { return }
            Task {
                await usage.refresh()
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
            ForEach(PanelPage.allCases.filter { $0 != .settings }) { page in
                navigationButton(page)
            }
            navigationButton(.settings).padding(.top, 12)
            Spacer()
        }
        .background {
            PanelSelectionIndicator(selection: navigation.page, namespace: navigationSelection)
        }
        .buttonStyle(.plain).font(.system(size: 13)).padding(12).frame(width: 188)
    }

    private func navigationButton(_ page: PanelPage) -> some View {
        Button { navigation.page = page } label: {
            HStack(spacing: 8) {
                Image(systemName: page.symbol).frame(width: 22, height: 22)
                Text(page.rawValue)
                Spacer(minLength: 0)
                if page == .settings, let release = updates.release, release.isNewer {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel(release.status).help(release.status)
                }
            }
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).padding(.horizontal, 10)
                .foregroundStyle(.primary)
                .modifier(PanelSelectionLabel(selection: navigation.page, namespace: navigationSelection))
                .contentShape(Rectangle())
        }.matchedGeometryEffect(id: page, in: navigationSelection)
            .help(page.rawValue)
            .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(navigation.page == .overview ? "用量统计" : navigation.page.rawValue).font(.system(size: 18, weight: .semibold))
            Spacer()
            if navigation.page != .settings && (navigation.page == .quota ? model.refreshing : usage.refreshing) {
                ProgressView().controlSize(.small)
            }
            if navigation.page != .settings {
                Button {
                    if navigation.page == .quota { Task { await model.refresh(force: true) } }
                    else { Task { await usage.refresh() } }
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(navigation.page == .quota ? model.refreshing || !model.monitoringEnabled : usage.refreshing)
            }
        }.padding(.horizontal, 24).frame(height: 56)
    }

    private var quotaContent: some View {
        let snapshot = model.snapshot
        return ScrollView {
            VStack(spacing: 16) {
                if model.monitoringEnabled {
                    QuotaBlock(windows: snapshot.windows, error: snapshot.errorMessage,
                               lastSuccess: snapshot.lastSuccess, refreshing: snapshot.refreshing)
                        .panelCard()
                    QuotaTrendView(history: model.quotaHistory, windows: snapshot.windows)
                    ResetAnnouncementView(model: resetAnnouncements).panelCard()
                } else {
                    VStack(spacing: 12) {
                        Text("额度监测已关闭").foregroundStyle(.secondary)
                        Button("开启监测") { model.setMonitoringEnabled(true) }
                    }.frame(maxWidth: .infinity, minHeight: 240)
                }
            }.frame(maxWidth: 760).padding(24).frame(maxWidth: .infinity)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppUpdateView(model: updates)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("监测额度")
                    Spacer()
                    Toggle("监测额度", isOn: Binding(get: { model.monitoringEnabled }, set: { model.setMonitoringEnabled($0) })).labelsHidden()
                }
                Divider()
                HStack {
                    Text("刷新间隔")
                    Spacer()
                    if showsRefreshIntervalEditor {
                        HStack(spacing: 8) {
                            TextField("至少 30", text: $refreshIntervalInput)
                                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                                .monospacedDigit().frame(width: 64)
                                .accessibilityLabel("刷新间隔（秒）")
                                .focused($refreshIntervalFocused)
                                .onSubmit(commitRefreshInterval)
                                .onChange(of: refreshIntervalFocused) { focused in
                                    if !focused { commitRefreshInterval() }
                                }
                                .help("最少 30 秒")
                            Text("秒").foregroundStyle(.secondary)
                        }
                            .onAppear {
                                // 等输入框挂载并结束按钮点击，再转移键盘焦点。
                                DispatchQueue.main.async { refreshIntervalFocused = true }
                            }
                            .onDisappear(perform: commitRefreshInterval)
                    } else {
                        Button {
                            refreshIntervalInput = String(model.refreshInterval)
                            showsRefreshIntervalEditor = true
                        } label: {
                            Text(refreshIntervalLabel(model.refreshInterval)).monospacedDigit()
                        }.accessibilityLabel("编辑刷新间隔")
                            .accessibilityValue(refreshIntervalLabel(model.refreshInterval))
                    }
                }
                Divider()
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
            VStack(alignment: .leading, spacing: 8) {
                Text("通知").font(.headline)
                HStack {
                    Text("额度恢复时通知")
                    Spacer()
                    Toggle("额度恢复时通知", isOn: Binding(get: { model.recoveryNotificationsEnabled }, set: { model.setRecoveryNotificationsEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!model.monitoringEnabled)
                }
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
                        .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!model.monitoringEnabled)
                        .help("提醒 Tibo 的重置预告、确认与发卡消息，个人额度恢复通知仍由实际读数触发。")
                }
            }.padding(16).panelCard()
            usageHistorySettings
            PricingSettingsView(model: usage).padding(16).panelCard()
            HStack {
                Text(appName)
                Spacer()
                Link("致谢 cc-bar · MIT", destination: URL(string: "https://github.com/nanvon/cc-bar")!)
                    .buttonStyle(.link)
            }.font(PanelTypography.detail).foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
    }

    private func refreshIntervalLabel(_ seconds: Int) -> String {
        if seconds.isMultiple(of: 3600) { return "\(seconds / 3600) 小时" }
        return seconds.isMultiple(of: 60) ? "\(seconds / 60) 分钟" : "\(seconds) 秒"
    }

    private func commitRefreshInterval() {
        let seconds = Int(refreshIntervalInput.trimmingCharacters(in: .whitespacesAndNewlines))
        model.setRefreshInterval(seconds ?? model.refreshInterval)
        refreshIntervalInput = String(model.refreshInterval)
        refreshIntervalFocused = false
        showsRefreshIntervalEditor = false
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
                Text("仅清除本应用保存的 Codex 用量历史，随后重新扫描现存日志。已删除源日志对应的历史将无法恢复；源日志与模型定价不会被删除。")
            }
    }

}

private struct QuotaBlock: View {
    let windows: [QuotaWindow]
    let error: String?
    let lastSuccess: Date?
    let refreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                CodexServiceTile()
                Text("Codex").font(.headline)
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
