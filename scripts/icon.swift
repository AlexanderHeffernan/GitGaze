import AppKit

// A record dial, matching the native menu-bar instrument at every icon resolution.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("GitGlaze.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.085, green: 0.087, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88), xRadius: p * 0.19, yRadius: p * 0.19).fill()
        for tick in 0..<32 {
            let angle = Double.pi / 2 - Double(tick) * Double.pi / 16
            NSColor(calibratedRed: 0.69, green: 0.61, blue: 1, alpha: tick < 25 ? 0.6 + CGFloat(tick) / 65 : 0.14).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: p * (0.5 + cos(angle) * 0.25), y: p * (0.5 + sin(angle) * 0.25)))
            line.line(to: NSPoint(x: p * (0.5 + cos(angle) * 0.32), y: p * (0.5 + sin(angle) * 0.32)))
            line.lineWidth = p * 0.018
            line.lineCapStyle = .round
            line.stroke()
        }
        NSColor(calibratedRed: 0.87, green: 0.83, blue: 1, alpha: 1).setFill()
        let bolt = NSBezierPath()
        bolt.move(to: NSPoint(x: p * 0.53, y: p * 0.67))
        bolt.line(to: NSPoint(x: p * 0.39, y: p * 0.47))
        bolt.line(to: NSPoint(x: p * 0.49, y: p * 0.47))
        bolt.line(to: NSPoint(x: p * 0.46, y: p * 0.33))
        bolt.line(to: NSPoint(x: p * 0.61, y: p * 0.54))
        bolt.line(to: NSPoint(x: p * 0.51, y: p * 0.54))
        bolt.close(); bolt.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("GitGlaze.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
