import AppKit
import SwiftUI
import QuotaCore

@MainActor
private final class StubClient: QuotaClient {
    var result: Result<QuotaSample, Error>
    var calls = 0
    var stops = 0
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    init(used: Double = 40) {
        result = .success(QuotaSample(fingerprint: "fixture", windows: [QuotaWindow(id: "fixture", usedPercent: used)]))
    }
    func sample() async throws -> QuotaSample {
        calls += 1
        if hold { await withCheckedContinuation { continuation = $0 } }
        return try result.get()
    }
    func release() { hold = false; continuation?.resume(); continuation = nil }
    func stop() { stops += 1; release() }
}

@main
struct AppChecks {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(value(), message)
        }
        let suite = "QuotaAppChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ServicePreferences(defaults: defaults)
        preferences.setNotificationsEnabled(false, for: .codex)
        let codex = StubClient()
        let model = MonitorModel(defaults: defaults, client: codex)

        // 同时触发刷新不会重入 Codex 客户端。
        codex.hold = true
        let first = Task { await model.refresh(force: true) }
        while codex.continuation == nil { await Task.yield() }
        expect(model.snapshot.refreshing, "挂起请求应保持刷新状态")
        await model.refresh(force: true)
        expect(codex.calls == 1, "Codex 刷新发生并发重入")
        codex.release()
        await first.value

        // 失败保留读数和成功时间，并标记错误。
        let previous = model.snapshot
        codex.result = .failure(MonitorError.message("fixture offline"))
        await model.refresh(force: true)
        expect(model.snapshot.windows == previous.windows, "失败清空了快照")
        expect(model.snapshot.lastSuccess == previous.lastSuccess, "失败更新了成功时间")
        expect(model.snapshot.errorMessage != nil, "缺少失败标记")

        // 关闭监测停止后续请求；设置重新实例化仍保持关闭。
        model.setMonitoringEnabled(false)
        let codexCalls = codex.calls
        await model.refresh(force: true)
        expect(codex.calls == codexCalls, "已关闭监测仍被查询")
        let reopened = MonitorModel(defaults: defaults, client: codex)
        expect(!reopened.monitoringEnabled, "监测开关未持久化")
        expect(!reopened.recoveryNotificationsEnabled, "通知开关未持久化")
        model.stop()
        reopened.stop()
        preferences.setEnabled(true, for: .codex)

        // 429 即使手动刷新也不立即重试。
        let limitedClient = StubClient()
        limitedClient.result = .failure(QuotaHTTPError(status: 429, retryAfter: 600))
        let limitedModel = MonitorModel(defaults: defaults, client: limitedClient)
        await limitedModel.refresh(force: true)
        let limitedCalls = limitedClient.calls
        await limitedModel.refresh(force: true)
        expect(limitedClient.calls == limitedCalls, "手动刷新绕过了限流")
        limitedModel.stop()

        // 停止后的请求不发布结果。
        let pendingClient = StubClient()
        let pendingModel = MonitorModel(defaults: defaults, client: pendingClient)
        pendingClient.hold = true
        let pending = Task { await pendingModel.refresh(force: true) }
        while pendingClient.continuation == nil { await Task.yield() }
        let finalSnapshot = pendingModel.snapshot
        pendingModel.stop()
        await pending.value
        expect(pendingModel.snapshot.lastSuccess == finalSnapshot.lastSuccess, "停止后仍发布了结果")
        expect(pendingClient.stops > 0, "退出未停止客户端")

        // 菜单提供面板入口和退出；关闭或重复打开面板不创建新的监测任务。
        let panelClient = StubClient()
        let panelModel = MonitorModel(defaults: defaults, client: panelClient)
        let panel = ControlPanelController(model: panelModel, activatesApplication: false)
        let menuBar = MenuBarController(model: panelModel) { panel.showPanel() }
        let window = panel.window!
        expect(menuBar.menu.items.count == 3 && menuBar.menu.items[0].action != nil
               && menuBar.menu.items[1].isSeparatorItem
               && menuBar.menu.items[2].action == #selector(NSApplication.terminate(_:))
               && menuBar.menu.items[2].target === NSApp,
               "菜单栏应提供打开面板、分隔线和退出应用的操作")
        expect(!window.isVisible, "启动时不应自动展开面板")
        menuBar.menu.performActionForItem(at: 0)
        expect(window.isVisible, "菜单入口未打开独立窗口")
        menuBar.menu.performActionForItem(at: 0)
        expect(panel.window === window && window.isVisible, "重复打开未复用面板")
        panel.close()
        expect(!window.isVisible, "关闭操作未收起面板")
        expect(panelClient.calls == 0 && panelClient.stops == 0, "面板开关改变了监测生命周期")
        await panelModel.refresh(force: true)
        expect(panelModel.snapshot.windows.first?.remaining == 60, "面板关闭后监测无法更新额度")
        menuBar.menu.performActionForItem(at: 0)
        expect(panel.window === window && window.isVisible, "关闭后无法重新打开同一个面板")
        expect(panelClient.calls == 1, "重新打开面板重复发起额度请求")
        menuBar.stop()
        panel.close()
        panelModel.stop()
        expect(!window.isVisible && panelClient.stops == 1, "退出未清理面板和客户端")

        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            try await renderPreviews(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]), defaults: defaults)
        }
        print("PASS: 5 个监测场景及菜单/面板生命周期，\(checks) 个断言（模拟客户端，无真实凭据或网络请求）")
    }

    @MainActor private static func renderPreviews(directory: URL, defaults: UserDefaults) async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferences = ServicePreferences(defaults: defaults)
        preferences.setEnabled(true, for: .codex)
        let now = Date()
        let client = StubClient()
        client.result = .success(QuotaSample(fingerprint: "fixture", windows: [
            QuotaWindow(id: "codex:short", bucket: "codex", name: "Codex", usedPercent: 10,
                        durationMinutes: 300, resetsAt: now.addingTimeInterval(12531), label: "5 小时额度"),
            QuotaWindow(id: "codex:week", bucket: "codex", name: "Codex", usedPercent: 42,
                        durationMinutes: 10080, resetsAt: now.addingTimeInterval(266400), label: "7 天额度")
        ]))
        let model = MonitorModel(defaults: defaults, client: client)
        await model.refresh(force: true)
        let size = NSSize(width: 1140, height: 860)
        for (name, page) in [("quota", PanelPage.quota), ("settings", .settings)] {
            let host = NSHostingView(rootView: MainView(model: model, navigation: PanelNavigation(page: page))
                .environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: .aqua)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw MonitorError.message("无法生成面板预览：\(name)")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw MonitorError.message("无法编码面板预览：\(name)")
            }
            try data.write(to: directory.appendingPathComponent(name + ".png"))
        }
        let image = MenuBarImageRenderer.image(
            windows: MenuBarImageRenderer.displayedWindows(from: model.snapshot.windows), hasError: false)
        let canvas = NSImage(size: image.size)
        canvas.lockFocus()
        NSColor(white: 0.94, alpha: 1).setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        canvas.unlockFocus()
        guard let data = canvas.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw MonitorError.message("无法生成菜单栏预览")
        }
        try png.write(to: directory.appendingPathComponent("menu.png"))
        model.stop()
    }
}
