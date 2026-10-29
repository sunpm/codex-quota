import AppKit
import SwiftUI
import UserNotifications
import QuotaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = MonitorModel()
    private var menuBar: MenuBarController?
    private var controlPanel: ControlPanelController?
    private var iconAppearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        iconAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.updateAppIcon() }
        }
        UNUserNotificationCenter.current().delegate = self
        buildMenu()
        controlPanel = ControlPanelController(model: model)
        model.updates.showSettings = { [weak self] in self?.showSettings() }
        menuBar = MenuBarController(model: model) { [weak self] in self?.showPanel() }
        model.start()
        showPanel()
    }

    @objc func showSettings() { controlPanel?.showSettings() }

    @objc func showPanel() { controlPanel?.showPanel() }

    private func updateAppIcon() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard let url = Bundle.main.url(forResource: dark ? "AppIconDark" : "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = image
    }

    private func buildMenu() {
        let menu = NSMenu()
        let root = NSMenuItem()
        menu.addItem(root)
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Codex Quota"
        let appMenu = NSMenu(title: appName)
        root.submenu = appMenu
        let show = NSMenuItem(title: "打开面板", action: #selector(showPanel), keyEquivalent: "0")
        show.target = self
        appMenu.addItem(show)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = NSMenu(title: "文件")
        menu.addItem(withTitle: "文件", action: nil, keyEquivalent: "").submenu = fileMenu
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenu = NSMenu(title: "编辑")
        menu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "").submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "窗口")
        menu.addItem(withTitle: "窗口", action: nil, keyEquivalent: "").submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        iconAppearanceObservation?.invalidate()
        iconAppearanceObservation = nil
        menuBar?.stop(); controlPanel?.close(); model.stop()
    }
    func applicationDidBecomeActive(_ notification: Notification) { Task { await model.updateNotificationStatus() } }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let postID = response.notification.request.content.userInfo["resetPostID"] as? String
        Task { @MainActor in
            if let postID, let url = ResetAnnouncementPost.sourceURL(for: postID) { NSWorkspace.shared.open(url) }
            else { self.showPanel() }
            completionHandler()
        }
    }
}

@main
struct CodexQuotaApp {
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
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
