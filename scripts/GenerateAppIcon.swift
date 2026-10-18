import AppKit

// Reproducible, vector-drawn macOS app icon; no external assets.
let destination = CommandLine.arguments.dropFirst().first ?? "Todoloo/Assets.xcassets/AppIcon.appiconset"
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (size, scale) in sizes {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
    (transform as NSAffineTransform).concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 75, y: 75, width: 874, height: 874), xRadius: 200, yRadius: 200)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(srgbRed: 0.13, green: 0.32, blue: 0.24, alpha: 1).setFill()
    tile.fill()
    NSShadow().set()
    NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.49, blue: 0.36, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.28, blue: 0.22, alpha: 1))!.draw(in: tile, angle: -90)
    let paper = NSBezierPath(roundedRect: NSRect(x: 240, y: 215, width: 544, height: 594), xRadius: 110, yRadius: 110)
    NSColor(srgbRed: 0.96, green: 0.96, blue: 0.88, alpha: 1).setFill()
    paper.fill()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 350, y: 502))
    line.line(to: NSPoint(x: 465, y: 390))
    line.line(to: NSPoint(x: 678, y: 628))
    line.lineWidth = 59
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    NSColor(srgbRed: 0.16, green: 0.39, blue: 0.29, alpha: 1).setStroke()
    line.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let filename = "icon_\(size)x\(size)@\(scale)x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
    images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: destination).appendingPathComponent("Contents.json"))
