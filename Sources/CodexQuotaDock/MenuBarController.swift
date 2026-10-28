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
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let item = NSMenuItem(title: "打开主窗口", action: #selector(showPanel), keyEquivalent: "")
        item.target = self
        menu.addItem(item)

        render()
        subscription = model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.render() }
    }

    @objc private func showPanel() { openPanel() }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true,
           let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else {
            openPanel()
        }
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func render() {
        let services = model.menuBarServices
        statusItem.isVisible = model.showsMenuBar && !services.isEmpty
        guard statusItem.isVisible else { return }
        guard let button = statusItem.button else { return }
        let entries = services.map { service in
            let snapshot = model.snapshot(service)
            return MenuBarImageRenderer.Entry(service: service, windows: snapshot.windows, hasError: snapshot.errorMessage != nil)
        }
        let image = MenuBarImageRenderer.image(entries: entries)
        statusItem.length = image.size.width + 8
        button.image = image
        let description = entries.map { entry in
            let details = entry.windows.map { window in
                let reset = window.resetsAt.map { "，\($0.formatted(date: .abbreviated, time: .shortened)) 重置" } ?? ""
                return "\(window.displayLabel)：剩余 \(window.percentageText)\(reset)"
            }.joined(separator: "；")
            return "\(entry.service.title)：\(details.isEmpty ? "等待数据" : details)"
        }.joined(separator: "\n")
        let errors = services.compactMap { service in model.snapshot(service).errorMessage.map { "\(service.title)：\($0)" } }
        let status = errors.isEmpty ? description : "额度可能已过期：\(errors.joined(separator: "\n"))"
        button.setAccessibilityLabel("服务额度。\(status)。单击打开主窗口。")
        button.toolTip = "\(status)\n单击打开主窗口 · 右键打开菜单"
    }
}
