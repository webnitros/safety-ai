// Renders app/AppIcon.icns. Run from the repo root:
//   swiftc app/make-icon.swift -o /tmp/make-icon && /tmp/make-icon app
import AppKit

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "app"
let iconset = dir + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

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
    NSGradient(starting: NSColor(red: 0.98, green: 0.45, blue: 0.20, alpha: 1),
               ending: NSColor(red: 0.85, green: 0.16, blue: 0.24, alpha: 1))!.draw(in: path, angle: -90)

    // palette: lock in the gradient color, shield in white
    let cfg = NSImage.SymbolConfiguration(pointSize: body.width * 0.56, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(red: 0.90, green: 0.25, blue: 0.22, alpha: 1), .white]))
    let sym = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let sz = sym.size
    sym.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

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
