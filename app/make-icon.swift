// Renders app/AppIcon.icns and docs/logo.png: a white shield with a neural-network mark on red.
// Run from the repo root:
//   swiftc app/make-icon.swift -o /tmp/make-icon && /tmp/make-icon app docs
import AppKit

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "app"
let docs = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "docs"
let iconset = dir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let red = NSColor(red: 0.74, green: 0.09, blue: 0.16, alpha: 1)

func symbol(_ name: String, _ size: CGFloat, _ color: NSColor) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
}

func drawCentered(_ img: NSImage, _ x: CGFloat, _ y: CGFloat) {
    let sz = img.size
    img.draw(in: NSRect(x: x - sz.width / 2, y: y - sz.height / 2, width: sz.width, height: sz.height))
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: 824/1024 body with rounded corners
    let body = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(starting: NSColor(red: 0.95, green: 0.27, blue: 0.27, alpha: 1), ending: red)!.draw(in: path, angle: -90)

    drawCentered(symbol("shield.fill", body.width * 0.5, .white), s / 2, s / 2)
    drawCentered(symbol("point.3.connected.trianglepath.dotted", body.width * 0.27, red), s / 2, s / 2 + s * 0.02)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
try! render(256).write(to: URL(fileURLWithPath: docs + "/logo.png"))

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", dir + "/AppIcon.icns"]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconset)
print("wrote \(dir)/AppIcon.icns")
