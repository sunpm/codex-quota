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
    @State private var showsPricingSettings = false
    @AppStorage("usage.sidebarToday.v1") private var sidebarToday = UsageTodayMetric.tokens.rawValue
    @AppStorage("usage.columns.speed") private var showsUsageSpeed = true
    @AppStorage("usage.columns.firstToken") private var showsUsageFirstToken = true
    @AppStorage("usage.columns.cacheWrite") private var showsUsageCacheWrite = false
    @AppStorage("usage.columns.billingTier") private var showsUsageBillingTier = false
    @State private var refreshIntervalInput: String
    @State private var showsRefreshIntervalEditor = false
    @FocusState private var refreshIntervalFocused: Bool
    @Namespace private var navigationSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: MonitorModel, showsSettings: Bool = false, navigation: PanelNavigation? = nil) {
        self.model = model
        _resetAnnouncements = ObservedObject(wrappedValue: model.resetAnnouncements)
        _updates = ObservedObject(wrappedValue: model.updates)
        _refreshIntervalInput = State(initialValue: String(model.refreshInterval))
        _navigation = StateObject(wrappedValue: navigation ?? PanelNavigation(page: showsSettings ? .settings : .overview))
    }

    var body: some View {
        HStack(spacing: 0) {
            #if compiler(>=6.2)
            if #available(macOS 26, *) {
                sidebar.glassEffect(in: RoundedRectangle(cornerRadius: 16)).padding(8)
            } else {
                sidebar.background(Color(nsColor: .windowBackgroundColor))
                Divider()
            }
            #else
            sidebar.background(Color(nsColor: .windowBackgroundColor))
            Divider()
            #endif
            VStack(spacing: 0) {
                header
                Divider()
                if navigation.page == .settings {
                    ScrollView { settings.frame(maxWidth: .infinity).padding(24) }
                } else if navigation.page == .quota {
                    quotaContent
                } else {
                    UsageView(model: usage, page: navigation.page)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, idealWidth: 1140, minHeight: 560, idealHeight: 760)
        .buttonStyle(PanelButtonStyle())
        .environment(\.panelAnimationsEnabled, model.animationsEnabled && !reduceMotion)
        .onChange(of: model.monitoringEnabled) { enabled in
            if !enabled { showsRefreshIntervalEditor = false }
        }
        .sheet(isPresented: $updates.showsInstalledReleaseNotes) {
            InstalledReleaseNotesView(version: updates.currentVersion, markdown: updates.installedReleaseNotes)
                .onAppear { updates.markInstalledReleaseNotesShown() }
        }
        .alert("开启持久通知", isPresented: $model.showsPersistentNotificationGuide) {
            Button("前往设置…") { model.openNotificationSettings() }
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
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Codex Quota"
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
        Button {
            guard navigation.page != page else { return }
            navigation.page = page
            if page == .quota { Task { await model.refresh(force: true) } }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
              HStack(spacing: 8) {
                Image(systemName: page.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 14)).fontWeight(.regular)
                    .frame(width: 22, height: 22)
                Text(page.rawValue)
                Spacer(minLength: 0)
                if page == .settings, let release = updates.release, release.isNewer {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(navigation.page == .settings && (!model.animationsEnabled || reduceMotion)
                                         ? Color.white : Color.accentColor)
                        .accessibilityLabel(release.status).help(release.status)
                }
              }
              if page == .overview, sidebarToday != 0 {
                  sidebarTodaySummary.padding(.leading, 30)
              }
            }
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).padding(.horizontal, 10)
                .modifier(PanelSelectionLabel(value: page, selection: navigation.page, namespace: navigationSelection))
                .contentShape(Rectangle())
        }.help(page.rawValue)
            .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
    }

    private var sidebarTodaySummary: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let records = usage.scan.records.filter { $0.date >= today && $0.date <= Date() }
        let tokens = records.reduce(into: UsageTokens()) { $0.add($1.tokens) }
        let cost = usage.costTotal(records)
        let items = UsageTodayMetric.allCases.filter { sidebarToday & $0.rawValue != 0 }.prefix(2)
        return HStack(alignment: .top, spacing: 4) {
            Text("今日")
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(Array(items), id: \.self) { item in
                    if usage.updatedAt == nil {
                        Text("—").help(item.title)
                    } else {
                        switch item {
                        case .tokens:
                            Text("\(formattedTokens(tokens.total)) Tokens").help("今日 \(tokens.total.formatted()) Tokens")
                        case .cost:
                            Text(cost.unpricedCount > 0 && cost.pricedCount > 0
                                 ? "已定价 \(formattedCost(cost))"
                                 : records.isEmpty ? "$0.00" : formattedCost(cost))
                                .help("API 等价估算，非订阅账单。\(cost.unpricedCount) 条未定价。")
                        case .records:
                            Text("\(formattedTokens(records.count)) 条").help("今日 \(records.count.formatted()) 条用量记录，不代表全部网络请求数")
                        case .hitRate:
                            Text("\(tokens.cacheHitRate.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—") 命中")
                                .help("缓存命中量 ÷ 全部输入")
                        }
                    }
                }
            }
        }.font(PanelTypography.detail).monospacedDigit().lineLimit(1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(navigation.page.rawValue).font(.system(size: 18, weight: .semibold))
            Spacer()
            if navigation.page != .settings && navigation.page != .quota {
                if usage.refreshing { ProgressView().controlSize(.small) }
                Button {
                    Task { await usage.refresh() }
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(usage.refreshing)
            }
        }.padding(.horizontal, 24).frame(height: 56)
    }

    private var quotaContent: some View {
        let snapshot = model.snapshot
        return ScrollView {
            VStack(spacing: 16) {
                if model.monitoringEnabled {
                    QuotaBlock(windows: snapshot.windows, resetCredits: snapshot.resetCredits, error: snapshot.errorMessage)
                        .panelCard()
                    QuotaTrendView(history: model.quotaHistory, windows: snapshot.windows)
                    ResetAnnouncementView(model: resetAnnouncements).panelCard()
                } else {
                    VStack(spacing: 12) {
                        Text("额度监测已关闭").foregroundStyle(.secondary)
                        Button("开启监测") { model.setMonitoringEnabled(true) }
                    }.frame(maxWidth: .infinity, minHeight: 240)
                }
            }.frame(maxWidth: .infinity).padding(24)
        }
    }

    private var settings: some View {
        let presetIntervals = [30, 60, 120, 300, 600, 1800]
        let refreshIntervals = presetIntervals.contains(model.refreshInterval)
            ? presetIntervals : presetIntervals + [model.refreshInterval]
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("额度监测").font(.headline)
                    Spacer()
                    Toggle("额度监测", isOn: Binding(get: { model.monitoringEnabled }, set: { model.setMonitoringEnabled($0) })).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("刷新间隔")
                        Spacer()
                        Menu {
                            ForEach(refreshIntervals, id: \.self) { seconds in
                                Toggle(refreshIntervalLabel(seconds), isOn: Binding(
                                    get: { seconds == model.refreshInterval },
                                    set: { _ in model.setRefreshInterval(seconds) }
                                )).toggleStyle(.automatic)
                            }
                            Divider()
                            Button("自定义…") {
                                refreshIntervalInput = String(model.refreshInterval)
                                showsRefreshIntervalEditor = true
                            }
                        } label: {
                            Text(refreshIntervalLabel(model.refreshInterval)).monospacedDigit().lineLimit(1)
                        }.fixedSize()
                            .accessibilityLabel("刷新间隔")
                            .accessibilityValue(refreshIntervalLabel(model.refreshInterval))
                            .popover(isPresented: $showsRefreshIntervalEditor, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Text("刷新间隔（秒）")
                                        TextField("至少 30", text: $refreshIntervalInput)
                                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                                            .monospacedDigit().frame(width: 80)
                                            .accessibilityLabel("刷新间隔（秒）")
                                            .focused($refreshIntervalFocused)
                                            .onSubmit(commitRefreshInterval)
                                            .help("最少 30 秒")
                                    }
                                    HStack {
                                        Spacer()
                                        Button("取消") { showsRefreshIntervalEditor = false }
                                            .keyboardShortcut(.cancelAction)
                                        Button("保存", action: commitRefreshInterval)
                                            .buttonStyle(PanelButtonStyle(prominent: true))
                                            .keyboardShortcut(.defaultAction)
                                    }
                                }.font(.system(size: 13)).padding(16)
                                    .onAppear {
                                        DispatchQueue.main.async { refreshIntervalFocused = true }
                                    }
                            }
                    }.frame(height: 24)
                    HStack {
                        Text("额度恢复时通知")
                        Spacer()
                        Toggle("额度恢复时通知", isOn: Binding(get: { model.recoveryNotificationsEnabled }, set: { model.setRecoveryNotificationsEnabled($0) })).labelsHidden()
                    }
                    HStack {
                        Text("重置卡到期前 24 小时提醒")
                        Spacer()
                        Toggle("重置卡到期前 24 小时提醒", isOn: Binding(get: { model.resetCreditRemindersEnabled },
                            set: { model.setResetCreditRemindersEnabled($0) })).labelsHidden()
                            .help("提前 24 小时提醒，每张卡仅提醒一次；需保持应用运行和额度监测开启。")
                    }
                    HStack {
                        Text("Codex 重置动态通知")
                        Spacer()
                        Toggle("Codex 重置动态通知", isOn: Binding(get: { resetAnnouncements.notificationsEnabled },
                            set: { model.setResetNotificationsEnabled($0) })).labelsHidden()
                            .help("提醒 Tibo 的重置预告、确认与发卡消息，个人额度恢复通知仍由实际读数触发。")
                    }
                }.padding(.leading, 12)
                    .disabled(!model.monitoringEnabled)
                    .saturation(model.monitoringEnabled ? 1 : 0)
                    .opacity(model.monitoringEnabled ? 1 : 0.45)
            }.toggleStyle(.switch).controlSize(.small).padding(16).panelCard()
            VStack(alignment: .leading, spacing: 8) {
                Text("系统通知").font(.headline)
                Text(model.notificationStatus).font(PanelTypography.detail).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    if !model.persistentNotificationsEnabled {
                        Button("开启持久通知…") { model.showPersistentNotificationGuide() }
                    }
                    Button("测试通知") { Task { await model.sendTestNotification() } }
                        .disabled(!model.monitoringEnabled || !model.notificationsEnabled
                                  || !(model.recoveryNotificationsEnabled || model.resetCreditRemindersEnabled
                                       || resetAnnouncements.notificationsEnabled))
                    Button("系统设置…") { model.openNotificationSettings() }
                }
                if let error = model.notificationError { Text(error).font(PanelTypography.detail).foregroundStyle(.primary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).panelCard()
            VStack(alignment: .leading, spacing: 14) {
                Text("通用").font(.headline)
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
                Divider()
                HStack {
                    Text("动画特性")
                    Spacer()
                    Toggle("动画特性", isOn: Binding(get: { model.animationsEnabled }, set: { model.setAnimationsEnabled($0) })).labelsHidden()
                        .help("控制侧栏和选项切换时的滑动与文字过渡效果。")
                }
            }.toggleStyle(.switch).controlSize(.small).padding(16).panelCard()
            usageDisplaySettings
            HStack {
                Text("模型定价").font(.headline)
                Spacer()
                Button("管理定价…") { showsPricingSettings = true }
            }.padding(16).panelCard()
                .sheet(isPresented: $showsPricingSettings) {
                    PricingSettingsView(model: usage)
                }
            usageHistorySettings
            AppUpdateView(model: updates)
        }
        .font(.system(size: 13))
    }

    private var usageDisplaySettings: some View {
        let selected = UsageTodayMetric.allCases.filter { sidebarToday & $0.rawValue != 0 }
        return VStack(alignment: .leading, spacing: 14) {
            Text("用量显示").font(.headline)
            HStack {
                Text("侧栏今日用量")
                Spacer()
                Menu {
                    ForEach(UsageTodayMetric.allCases, id: \.self) { item in
                        Toggle(item.title, isOn: Binding(
                            get: { sidebarToday & item.rawValue != 0 },
                            set: { enabled in
                                if enabled { sidebarToday |= item.rawValue }
                                else { sidebarToday &= ~item.rawValue }
                            }))
                            .disabled(!selected.contains(item) && selected.count >= 2)
                    }
                    Divider()
                    Button("不显示") { sidebarToday = 0 }
                } label: {
                    Text(selected.isEmpty ? "不显示" : selected.map(\.title).joined(separator: " + "))
                }.help("最多显示两项，按本地自然日统计。")
            }
            Divider()
            HStack {
                Text("明细可选列")
                Spacer()
                Menu("选择列") {
                    Toggle("速度", isOn: $showsUsageSpeed)
                    Toggle("首字", isOn: $showsUsageFirstToken)
                    Toggle("缓存写入", isOn: $showsUsageCacheWrite)
                    Toggle("计费档位", isOn: $showsUsageBillingTier)
                }
            }
        }.padding(16).panelCard()
    }

    private func refreshIntervalLabel(_ seconds: Int) -> String {
        if seconds.isMultiple(of: 3600) { return "\(seconds / 3600) 小时" }
        return seconds.isMultiple(of: 60) ? "\(seconds / 60) 分钟" : "\(seconds) 秒"
    }

    private func commitRefreshInterval() {
        guard showsRefreshIntervalEditor else { return }
        if model.monitoringEnabled {
            let seconds = Int(refreshIntervalInput.trimmingCharacters(in: .whitespacesAndNewlines))
            model.setRefreshInterval(seconds ?? model.refreshInterval)
        }
        refreshIntervalInput = String(model.refreshInterval)
        refreshIntervalFocused = false
        showsRefreshIntervalEditor = false
    }

    private var usageHistorySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用量历史").font(.headline)
            HStack {
                Spacer()
                Button("重新扫描日志") { Task { await usage.refresh(rescan: true) } }
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
    let resetCredits: RateLimitResetCredits?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                CodexServiceTile()
                Text("Codex").font(.headline)
                Spacer(minLength: 0)
                Text("剩余").font(PanelTypography.detail).foregroundStyle(.secondary)
            }
            if windows.isEmpty {
                Text("暂无额度读数")
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
            if let resetCredits {
                Divider()
                ResetCreditsView(credits: resetCredits)
            }
            if let error {
                Label {
                    Text(windows.isEmpty && resetCredits == nil ? error : "数据已过期 · \(error)").foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(quotaColor(remaining: 10))
                }.font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
