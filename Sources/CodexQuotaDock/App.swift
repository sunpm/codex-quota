import AppKit
import SwiftUI
import UserNotifications
import QuotaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = MonitorModel()
    private var window: NSWindow?
    private var floatingPanel: FloatingQuotaPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        buildMenu()
        floatingPanel = FloatingQuotaPanelController(model: model) { [weak self] in self?.showWindow() }
        showFloatingPanel()
        model.start()
    }

    @objc func showFloatingPanel() { floatingPanel?.show() }

    @objc func showWindow() {
        if window == nil {
            let view = NSHostingView(rootView: MainView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 580), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Codex 额度 · 详情与设置"
            window.contentView = view
            window.setContentSize(view.fittingSize)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMenu() {
        let menu = NSMenu()
        let root = NSMenuItem()
        menu.addItem(root)
        let appMenu = NSMenu()
        root.submenu = appMenu
        let show = NSMenuItem(title: "显示悬浮面板", action: #selector(showFloatingPanel), keyEquivalent: "0")
        show.target = self
        appMenu.addItem(show)
        let settings = NSMenuItem(title: "详情与设置…", action: #selector(showWindow), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Codex 额度", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Codex 额度", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showFloatingPanel(); return true }
    func applicationWillTerminate(_ notification: Notification) { floatingPanel?.close(); model.stop() }
    func applicationDidBecomeActive(_ notification: Notification) { Task { await model.updateNotificationStatus() } }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showWindow(); completionHandler() }
    }
}

@main
struct CodexQuotaDockApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            Task { @MainActor in
                let client = CodexClient()
                do {
                    let sample = try await client.sample()
                    let summary = sample.windows.map { ["window": $0.id, "remaining": $0.percentageText] }
                    let data = try JSONSerialization.data(withJSONObject: ["loginReused": true, "windows": summary], options: [.prettyPrinted, .sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                    client.stop()
                    exit(0)
                } catch {
                    fputs("Probe failed: \(error.localizedDescription)\n", stderr)
                    client.stop()
                    exit(1)
                }
            }
            RunLoop.main.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
