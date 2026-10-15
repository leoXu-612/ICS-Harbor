import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func icon(_ size: Int, name: String) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = AffineTransform(scale: CGFloat(size) / 1024)
    (transform as NSAffineTransform).concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 25, y: 25, width: 974, height: 974), xRadius: 212, yRadius: 212)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.62, alpha: 1), ending: NSColor(calibratedRed: 0.24, green: 0.62, blue: 0.95, alpha: 1))!.draw(in: background, angle: 55)
    func shape(_ points: [NSPoint], alpha: CGFloat) {
        let p = NSBezierPath(); p.move(to: points[0]); for point in points.dropFirst() { p.line(to: point) }; p.close()
        NSColor.white.withAlphaComponent(alpha).setFill(); p.fill()
    }
    shape([.init(x: 250, y: 370), .init(x: 490, y: 775), .init(x: 490, y: 370)], alpha: 1)
    shape([.init(x: 533, y: 710), .init(x: 758, y: 370), .init(x: 533, y: 370)], alpha: 0.82)
    shape([.init(x: 214, y: 322), .init(x: 803, y: 322), .init(x: 691, y: 221), .init(x: 350, y: 221)], alpha: 1)
    let wave = NSBezierPath(); wave.move(to: .init(x: 235, y: 168)); wave.curve(to: .init(x: 505, y: 168), controlPoint1: .init(x: 330, y: 124), controlPoint2: .init(x: 401, y: 207)); wave.curve(to: .init(x: 781, y: 171), controlPoint1: .init(x: 600, y: 126), controlPoint2: .init(x: 680, y: 210))
    wave.lineWidth = 19; wave.lineCapStyle = .round; NSColor.white.withAlphaComponent(0.65).setStroke(); wave.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}
for points in [16, 32, 128, 256, 512] {
    try icon(points, name: "icon_\(points)x\(points).png")
    try icon(points * 2, name: "icon_\(points)x\(points)@2x.png")
}
