import AppKit
import Combine
import QuotaCore

@MainActor
final class MenuBarController: NSObject {
    private let model: MonitorModel
    private let statusItem: NSStatusItem
    private let openPanel: () -> Void
    let menu = NSMenu()
    private var subscription: AnyCancellable?

    init(model: MonitorModel, openPanel: @escaping () -> Void) {
        self.model = model
        self.openPanel = openPanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.autosaveName = "CodexQuotaMenuBar"
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }
        let item = NSMenuItem(title: "打开面板", action: #selector(showPanel), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "退出 Codex Quota Dock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        statusItem.menu = menu

        render()
        subscription = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
    }

    @objc private func showPanel() { openPanel() }

    func stop() {
        subscription?.cancel()
        subscription = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func render() {
        statusItem.isVisible = model.hasMenuBarItem
        guard statusItem.isVisible, let button = statusItem.button else { return }
        let snapshot = model.snapshot
        let image = MenuBarImageRenderer.image(windows: MenuBarImageRenderer.displayedWindows(from: snapshot.windows),
                                               hasError: snapshot.errorMessage != nil)
        statusItem.length = image.size.width + 8
        button.image = image
        let description = snapshot.windows.map { window in
            let reset = window.resetsAt.map { "，\($0.formatted(date: .abbreviated, time: .shortened)) 重置" } ?? ""
            return "\(window.displayLabel)：剩余 \(window.percentageText)\(reset)"
        }.joined(separator: "；")
        let status = snapshot.errorMessage.map { "额度可能已过期：\($0)" }
            ?? (description.isEmpty ? "等待数据" : description)
        button.setAccessibilityLabel("Codex 额度。\(status)。单击打开菜单。")
        button.toolTip = "\(status)\n单击打开菜单"
    }
}
