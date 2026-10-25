import AppKit

let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
        NSColor(calibratedRed: 0.08, green: 0.14, blue: 0.19, alpha: 1).setFill()
        background.fill()
        let track = NSBezierPath(ovalIn: NSRect(x: 224, y: 224, width: 576, height: 576))
        track.lineWidth = 68
        NSColor(calibratedRed: 0.18, green: 0.29, blue: 0.33, alpha: 1).setStroke()
        track.stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 288, startAngle: 90, endAngle: -208, clockwise: true)
        arc.lineWidth = 68
        arc.lineCapStyle = .round
        NSColor(calibratedRed: 0.32, green: 0.9, blue: 0.72, alpha: 1).setStroke()
        arc.stroke()
        let text = "%" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 260, weight: .medium), .foregroundColor: NSColor.white]
        let dimensions = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (1024 - dimensions.width) / 2, y: (1024 - dimensions.height) / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size)\(suffix).png"))
    }
}
