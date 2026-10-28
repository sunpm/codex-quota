import AppKit

let folder = CommandLine.arguments[1]
let dark = CommandLine.arguments.dropFirst(2).first == "dark"
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

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
        NSGradient(starting: color(dark ? 0x303739 : 0xFBFAF7),
                   ending: color(dark ? 0x1D2325 : 0xECECE7))!.draw(in: background, angle: -90)
        color(dark ? 0x434B4D : 0xDCDDD7).setStroke()
        background.lineWidth = 2
        background.stroke()

        // 原创缺口 Q：环代表额度，右下斜切保留独立品牌识别。
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: 490, y: 542), radius: 256,
                      startAngle: -12, endAngle: 282, clockwise: false)
        arc.lineWidth = 104
        arc.lineCapStyle = .butt
        color(dark ? 0xEEF1EE : 0x293334).setStroke()
        arc.stroke()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 606, y: 426))
        tail.line(to: NSPoint(x: 738, y: 294))
        tail.lineWidth = 104
        tail.lineCapStyle = .round
        color(dark ? 0x72D7CC : 0x087F79).setStroke()
        tail.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(folder)/icon_\(size)x\(size)\(suffix).png"))
    }
}
