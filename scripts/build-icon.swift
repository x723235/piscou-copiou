import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let set = root.appendingPathComponent("Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let n = CGFloat(pixels)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.06, y: n * 0.06, width: n * 0.88, height: n * 0.88), xRadius: n * 0.20, yRadius: n * 0.20).fill()
        let text = ">>" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: n * 0.53, weight: .heavy), .foregroundColor: NSColor(calibratedRed: 0.77, green: 1, blue: 0.22, alpha: 1)]
        let bounds = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (n - bounds.width) / 2, y: (n - bounds.height) / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: set.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        if pixels == 1024 { try data.write(to: root.appendingPathComponent("Resources/AppIcon.png")) }
    }
}
