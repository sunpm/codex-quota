import AppKit
import SwiftUI

/// 独立面板复用同一份监测数据；关闭窗口只隐藏界面，后台查询继续运行。
@MainActor
final class ControlPanelController: NSWindowController {
    private let navigation = PanelNavigation()

    init(model: MonitorModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Quota Dock"
        window.identifier = NSUserInterfaceItemIdentifier("control-panel")
        window.setFrameAutosaveName("ControlPanel")
        window.contentMinSize = NSSize(width: 860, height: 560)
        // 保留窗口和页面状态，菜单入口、重新打开应用和通知共用此窗口。
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: MainView(model: model, navigation: navigation))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showSettings() {
        navigation.page = .settings
        showPanel()
    }

    func showPanel() {
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
