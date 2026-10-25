// Adapted from nanvon/cc-bar (MIT), MenuBar/MenuBarLabel.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import AppKit
import QuotaCore

@MainActor
enum CodexLogo {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "codex", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// cc-bar 的单色模板图像方案：系统负责菜单栏的深浅色和高亮着色。
@MainActor
enum MenuBarImageRenderer {
    struct Entry {
        let service: QuotaService
        let windows: [QuotaWindow]
        var hasError = false
    }

    static func image(entries: [Entry]) -> NSImage {
        guard !entries.isEmpty else {
            let paused = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "监测已关闭")!
            paused.isTemplate = true
            return paused
        }
        let images = entries.map { entry in
            image(windows: entries.count == 1 ? displayedWindows(from: entry.windows) : Array(entry.windows.prefix(1)),
                  hasError: entry.hasError, service: entry.service)
        }
        let width = images.reduce(CGFloat(0)) { $0 + $1.size.width } + CGFloat(max(0, images.count - 1)) * 9
        let result = NSImage(size: NSSize(width: width, height: 22))
        result.lockFocus()
        var x: CGFloat = 0
        for image in images {
            image.draw(at: NSPoint(x: x, y: 0), from: .zero, operation: .sourceOver, fraction: 1)
            x += image.size.width + 9
        }
        result.unlockFocus()
        result.isTemplate = true
        return result
    }

    static func displayedWindows(from windows: [QuotaWindow]) -> [QuotaWindow] {
        let codex = windows.filter { $0.bucket == "codex" }
        return Array((codex.isEmpty ? windows : codex).sorted {
            ($0.durationMinutes ?? Int.max) < ($1.durationMinutes ?? Int.max)
        }.prefix(2))
    }

    static func image(windows: [QuotaWindow], hasError: Bool, service: QuotaService = .codex) -> NSImage {
        let iconSize: CGFloat = 18
        let height: CGFloat = 22
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let percentages = windows.isEmpty ? "--" : windows.map(\.percentageText).joined(separator: "/")
        let text = (percentages + (hasError ? " !" : "")) as NSString
        let textSize = text.size(withAttributes: attributes)
        let result = NSImage(size: NSSize(width: iconSize + 3 + ceil(textSize.width), height: height))
        result.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: result.size).fill()
        let logo = (service == .codex ? CodexLogo.image : nil) ?? NSImage(systemSymbolName: service.symbol, accessibilityDescription: nil)
        logo?.draw(in: NSRect(x: 0, y: 2, width: iconSize, height: iconSize))
        text.draw(at: NSPoint(x: iconSize + 3, y: floor((height - textSize.height) / 2)), withAttributes: attributes)
        result.unlockFocus()
        result.isTemplate = true
        return result
    }

    /// 示例数据的离线视觉验收，不启动监听，不改动真实状态。
    static func writePreviews(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let short = QuotaWindow(id: "preview:short", usedPercent: 20, durationMinutes: 300, resetsAt: now.addingTimeInterval(15954))
        let week = QuotaWindow(id: "preview:week", usedPercent: 16, durationMinutes: 10080, resetsAt: now.addingTimeInterval(566736))
        let cases: [(String, [QuotaWindow], Bool, Bool)] = [
            ("single-light", [week], false, false),
            ("dual-light", [short, week], false, false),
            ("dual-dark", [short, week], true, false),
            ("offline-light", [week], false, true)
        ]
        for (name, windows, dark, failed) in cases {
            let result = image(windows: windows, hasError: failed)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(result.size.width * 2), pixelsHigh: 44, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSGraphicsContext.current?.cgContext.scaleBy(x: 2, y: 2)
            let rect = NSRect(origin: .zero, size: result.size)
            result.draw(in: rect)
            (dark ? NSColor.white : NSColor.black).setFill()
            rect.fill(using: .sourceAtop)
            NSColor(white: dark ? 0.15 : 0.94, alpha: 1).setFill()
            rect.fill(using: .destinationOver)
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
