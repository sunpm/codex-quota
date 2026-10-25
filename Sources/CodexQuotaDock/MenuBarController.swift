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
        let item = NSMenuItem(title: "打开控制面板…", action: #selector(showPanel), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
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
        guard let button = statusItem.button else { return }
        let entries = model.enabledServices.map { service in
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
        let summary = description.isEmpty ? "监测已关闭" : description
        let status = model.errorMessage.map { "额度可能已过期：\($0)" } ?? summary
        button.setAccessibilityLabel("服务额度。\(status)。打开菜单可进入控制面板。")
        button.toolTip = "\(status)\n每 \(Int(MonitorModel.refreshInterval)) 秒查询 · 点击菜单中的“打开控制面板…”进行操作"
    }
}
