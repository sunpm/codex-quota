import AppKit
import SwiftUI
import UserNotifications
import QuotaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = MonitorModel()
    private var menuBar: MenuBarController?
    private var controlPanel: ControlPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        buildMenu()
        controlPanel = ControlPanelController(model: model)
        menuBar = MenuBarController(model: model) { [weak self] in self?.showPanel() }
        model.start()
    }

    @objc func showPanel() { controlPanel?.showPanel() }

    private func buildMenu() {
        let menu = NSMenu()
        let root = NSMenuItem()
        menu.addItem(root)
        let appMenu = NSMenu()
        root.submenu = appMenu
        let show = NSMenuItem(title: "打开控制面板…", action: #selector(showPanel), keyEquivalent: "0")
        show.target = self
        appMenu.addItem(show)
        let settings = NSMenuItem(title: "额度与设置…", action: #selector(showPanel), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Codex 额度", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Codex 额度", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationWillTerminate(_ notification: Notification) { menuBar?.stop(); controlPanel?.close(); model.stop() }
    func applicationDidBecomeActive(_ notification: Notification) { Task { await model.updateNotificationStatus() } }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showPanel(); completionHandler() }
    }
}

@main
struct CodexQuotaDockApp {
    @MainActor
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-menu-previews"), CommandLine.arguments.count > index + 1 {
            NSApplication.shared.setActivationPolicy(.prohibited)
            do {
                try MenuBarImageRenderer.writePreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
            } catch { fputs("Preview failed: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
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
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
