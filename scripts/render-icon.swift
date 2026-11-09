// Renders Resources/AppIcon.icns from the same geometry as assets/icon.svg.
// Usage: swift scripts/render-icon.swift   (needs only the macOS SDK, no SVG tools)
import AppKit

func hex(_ s: String) -> CGColor {
    let v = UInt32(s.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let bg = hex("#B9A8F0"), paper = hex("#FFF8EE"), ink = hex("#2E2552"), accent = hex("#FF8F6B"), glow = hex("#FFD9A0")

// (x, y, w, h, radius, color) in the 1024 design space, y down.
let rects: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGColor)] = [
    (300, 250, 424, 524, 0, paper),
    (340, 404, 344, 76, 20, glow),
    (368, 344, 288, 34, 17, ink),
    (368, 425, 230, 34, 17, accent),
    (368, 506, 270, 34, 17, ink),
    (368, 587, 200, 34, 17, ink),
    (250, 190, 524, 112, 56, ink),
    (250, 722, 524, 112, 56, ink),
]
let dots: [(CGFloat, CGFloat, CGFloat)] = [(306, 246, 26), (306, 778, 26)]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let k = CGFloat(px) / 1024
    ctx.scaleBy(x: k, y: k)
    ctx.translateBy(x: 0, y: 1024); ctx.scaleBy(x: 1, y: -1) // y down, like the SVG
    ctx.translateBy(x: 100, y: 100); ctx.scaleBy(x: 0.8046875, y: 0.8046875)

    let body = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerWidth: 228, cornerHeight: 228, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -15 * k), blur: 34 * k, color: CGColor(srgbRed: 0.12, green: 0.09, blue: 0.2, alpha: 0.28))
    ctx.setFillColor(bg); ctx.addPath(body); ctx.fillPath()
    ctx.restoreGState()

    for (x, y, w, h, r, c) in rects {
        ctx.setFillColor(c)
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
    }
    ctx.setFillColor(paper)
    for (x, y, r) in dots { ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try render(pt).write(to: set.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try render(pt * 2).write(to: set.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
try render(1024).write(to: root.appendingPathComponent("assets/icon.png"))
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out.path]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
