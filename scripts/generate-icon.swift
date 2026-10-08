import AppKit
import Foundation

// Code-drawn icon: standard Apple symbol and native AppKit rasterization, no downloaded assets.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon context unavailable") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let edge = CGFloat(pixels), inset = edge * 0.07
        let background = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: edge - 2 * inset, height: edge - 2 * inset), xRadius: edge * 0.20, yRadius: edge * 0.20)
        let start = NSColor(calibratedRed: 0.21, green: 0.73, blue: 0.67, alpha: 1)
        let end = NSColor(calibratedRed: 0.10, green: 0.49, blue: 0.48, alpha: 1)
        NSGradient(starting: start, ending: end)?.draw(in: background, angle: -90)
        let config = NSImage.SymbolConfiguration(pointSize: edge * 0.59, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "checkerboard.shield", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let target = NSRect(x: edge * 0.22, y: edge * 0.21, width: edge * 0.56, height: edge * 0.58)
            symbol.draw(in: target)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon encoding unavailable") }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: directory.appendingPathComponent(name))
    }
}
