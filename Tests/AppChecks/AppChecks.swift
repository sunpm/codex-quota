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
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(value(), message)
        }
        let suite = "QuotaAppChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ServicePreferences(defaults: defaults)
        for service in QuotaService.allCases { preferences.setNotificationsEnabled(false, for: service) }
        let codex = StubClient(), claude = StubClient(), antigravity = StubClient(), cursor = StubClient()
        let clients: [QuotaService: QuotaClient] = [.codex: codex, .claude: claude, .antigravity: antigravity, .cursor: cursor]
        let model = MonitorModel(defaults: defaults, clients: clients)

        // 一个服务挂起时，其余服务仍能完成；同时触发刷新也不会重入同一客户端。
        claude.hold = true
        let first = Task { await model.refresh(force: true) }
        while claude.continuation == nil || model.snapshot(.cursor).lastSuccess == nil { await Task.yield() }
        expect(model.snapshot(.cursor).windows.count == 1, "慢服务阻塞了其他服务")
        expect(model.snapshot(.claude).refreshing, "挂起请求应保持刷新状态")
        await model.refresh(force: true)
        expect(claude.calls == 1, "同一服务发生并发重入")
        claude.release()
        await first.value

        // 失败保留该服务的读数和更新时间，其他服务继续成功。
        let previous = model.snapshot(.claude)
        claude.result = .failure(MonitorError.message("fixture offline"))
        await model.refresh(force: true)
        expect(model.snapshot(.claude).windows == previous.windows, "失败清空了快照")
        expect(model.snapshot(.claude).lastSuccess == previous.lastSuccess, "失败更新了成功时间")
        expect(model.snapshot(.claude).errorMessage != nil, "缺少失败标记")
        expect(model.snapshot(.cursor).errorMessage == nil, "失败污染了其他服务")

        // 关闭监测停止后续请求；设置重新实例化仍保持关闭。
        model.setEnabled(false, for: .cursor)
        let cursorCalls = cursor.calls
        await model.refresh(force: true)
        expect(cursor.calls == cursorCalls, "已关闭服务仍被查询")
        let reopened = MonitorModel(defaults: defaults, clients: clients)
        expect(!reopened.isEnabled(.cursor), "服务开关未持久化")
        expect(!reopened.notificationsEnabled(for: .claude), "通知开关未持久化")

        // 429 即使手动刷新也不立即重试。
        antigravity.result = .failure(QuotaHTTPError(status: 429, retryAfter: 600))
        await model.refresh(force: true)
        let limitedCalls = antigravity.calls
        await model.refresh(force: true)
        expect(antigravity.calls == limitedCalls, "手动刷新绕过了限流")

        // 取消钥匙串访问后，定时及唤醒刷新均不重复请求访问；手动刷新可以重试。
        claude.result = .failure(KeychainAccessDeclined(service: "Claude"))
        await model.refresh(force: true)
        let declinedCalls = claude.calls
        await model.refresh()
        await model.refresh(force: true, retryCredentials: false)
        expect(claude.calls == declinedCalls, "自动刷新重复请求钥匙串授权")
        await model.refresh(force: true)
        expect(claude.calls == declinedCalls + 1, "手动刷新未重试钥匙串访问")

        // 停止后的请求不发布结果。
        codex.hold = true
        let pending = Task { await model.refresh(force: true) }
        while codex.continuation == nil { await Task.yield() }
        let finalSnapshot = model.snapshot(.codex)
        model.stop()
        await pending.value
        expect(model.snapshot(.codex).lastSuccess == finalSnapshot.lastSuccess, "停止后仍发布了结果")
        expect(codex.stops > 0, "退出未停止客户端")

        // 菜单只提供面板入口；关闭或重复打开面板不创建新的监测任务。
        NSApplication.shared.setActivationPolicy(.accessory)
        let panelClient = StubClient()
        let panelModel = MonitorModel(defaults: defaults, clients: [.codex: panelClient])
        let panel = ControlPanelController(model: panelModel)
        let menuBar = MenuBarController(model: panelModel) { panel.showPanel() }
        let window = panel.window!
        expect(menuBar.menu.items.count == 1 && menuBar.menu.items[0].action != nil,
               "菜单栏只能保留打开面板的操作")
        expect(!window.isVisible, "启动时不应自动展开面板")
        menuBar.menu.performActionForItem(at: 0)
        expect(window.isVisible, "菜单入口未打开独立窗口")
        menuBar.menu.performActionForItem(at: 0)
        expect(panel.window === window && window.isVisible, "重复打开未复用面板")
        panel.close()
        expect(!window.isVisible, "关闭操作未收起面板")
        expect(panelClient.calls == 0 && panelClient.stops == 0, "面板开关改变了监测生命周期")
        await panelModel.refresh(force: true)
        expect(panelModel.snapshot(.codex).windows.first?.remaining == 60, "面板关闭后监测无法更新额度")
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
        print("PASS: 6 个监测场景及菜单/面板生命周期，\(checks) 个断言（模拟客户端，无真实凭据或网络请求）")
    }

    @MainActor private static func renderPreviews(directory: URL, defaults: UserDefaults) async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferences = ServicePreferences(defaults: defaults)
        var clients: [QuotaService: QuotaClient] = [:]
        let now = Date()
        for (index, service) in QuotaService.allCases.enumerated() {
            preferences.setEnabled(true, for: service)
            let client = StubClient()
            client.result = .success(QuotaSample(fingerprint: "fixture", windows: [
                QuotaWindow(id: service.rawValue + ":short", bucket: service.rawValue, name: service.title,
                            usedPercent: Double(index * 24 + 10), durationMinutes: 300,
                            resetsAt: now.addingTimeInterval(12531), label: service == .antigravity ? "Gemini Models · 5 hours" : "5 小时额度"),
                QuotaWindow(id: service.rawValue + ":week", bucket: service.rawValue, name: service.title,
                            usedPercent: 42, durationMinutes: 10080, resetsAt: now.addingTimeInterval(266400),
                            label: service == .antigravity ? "Claude and GPT models · Weekly" : "7 天额度")
            ]))
            clients[service] = client
        }
        let model = MonitorModel(defaults: defaults, clients: clients)
        await model.refresh(force: true)
        for (name, settings, dark, size) in [
            ("services", false, false, NSSize(width: 560, height: 640)),
            ("settings", true, false, NSSize(width: 560, height: 640)),
            ("services-dark", false, true, NSSize(width: 560, height: 640)),
            ("settings-compact", true, false, NSSize(width: 480, height: 440))
        ] {
            let host = NSHostingView(rootView: MainView(model: model, showsSettings: settings)
                .environment(\.colorScheme, dark ? .dark : .light).background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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
        let image = MenuBarImageRenderer.image(entries: QuotaService.allCases.map {
            MenuBarImageRenderer.Entry(service: $0, windows: model.snapshot($0).windows)
        })
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
