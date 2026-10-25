import AppKit
import SwiftUI
import Combine
import QuotaCore

/// 展示服务端实际返回的 Codex 窗口；单窗口不会补造第二份额度。
private func panelWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
    let codex = windows.filter { $0.bucket == "codex" }
    return Array((codex.isEmpty ? windows : codex).sorted {
        ($0.durationMinutes ?? Int.max) < ($1.durationMinutes ?? Int.max)
    }.prefix(2))
}

private struct PanelGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct FloatingQuotaView: View {
    @ObservedObject var model: MonitorModel
    let openSettings: () -> Void

    private let meterWidth: CGFloat = 108
    private let fill = Color(red: 0.49, green: 0.62, blue: 0.59)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                let windows = panelWindows(model.windows)
                if windows.isEmpty {
                    meter(window: nil, now: context.date)
                } else {
                    ForEach(windows) { window in
                        meter(window: window, now: context.date)
                    }
                }
                Button(action: openSettings) {
                    Image(systemName: model.errorMessage == nil ? "slider.horizontal.3" : "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.orange)
                        .frame(width: 24, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.errorMessage ?? "详情与设置")
                .accessibilityLabel("打开详情与设置")
            }
            .padding(.horizontal, 10)
            .frame(height: 60)
        }
        .background(PanelGlass())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }

    private func meter(window: QuotaWindow?, now: Date) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Rectangle()
                    .fill(model.errorMessage == nil ? fill.opacity(0.75) : Color.orange.opacity(0.4))
                    .frame(width: meterWidth * CGFloat((window?.remaining ?? 0) / 100))
                Text(window?.percentageText ?? "—")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: meterWidth)
            }
            .frame(width: meterWidth, height: 22)
            .clipShape(Capsule())
            Text(window?.compactResetCountdown(at: now) ?? "读取中…")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: meterWidth)
        }
        .help(window.map { "\($0.name) · \($0.periodText)\n拖动面板可调整位置" } ?? "正在读取额度")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(window.map { "\($0.periodText)，剩余 \($0.percentageText)，\($0.compactResetCountdown(at: now)) 后重置" } ?? "正在读取额度")
    }
}

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FloatingHostingView: NSHostingView<FloatingQuotaView> {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class FloatingQuotaPanelController {
    private let panel: NSPanel
    private var subscription: AnyCancellable?

    init(model: MonitorModel, openSettings: @escaping () -> Void) {
        let size = Self.size(columnCount: max(1, panelWindows(model.windows).count))
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Codex 额度悬浮面板"
        panel.identifier = NSUserInterfaceItemIdentifier("quotaFloatingPanel")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = FloatingHostingView(rootView: FloatingQuotaView(model: model, openSettings: openSettings))

        let restored = panel.setFrameUsingName("CodexQuotaFloatingPanel")
        panel.setFrameAutosaveName("CodexQuotaFloatingPanel")
        if !restored, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 18, y: visible.minY + 12))
        }
        resize(columnCount: max(1, panelWindows(model.windows).count))
        subscription = model.$windows
            .map { max(1, panelWindows($0).count) }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] count in self?.resize(columnCount: count) }
    }

    func show() { panel.orderFrontRegardless() }
    func close() { subscription?.cancel(); panel.close() }

    private static func size(columnCount: Int) -> NSSize {
        NSSize(width: CGFloat(columnCount) * 108 + CGFloat(columnCount - 1) * 12 + 56, height: 60)
    }

    private func resize(columnCount: Int) {
        let size = Self.size(columnCount: columnCount)
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.maxX - size.width, y: frame.minY, width: size.width, height: size.height), display: true)
    }
}
