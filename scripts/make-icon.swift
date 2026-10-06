import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(calibratedRed: 0.055, green: 0.068, blue: 0.09, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 212, yRadius: 212).fill()
    // Overwatch-style O/W emblem: orange crown, silver lower ring and W arms.
    let orange = NSColor(calibratedRed: 1, green: 0.47, blue: 0.13, alpha: 1)
    let silver = NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.98, alpha: 1)
    let center = NSPoint(x: 512, y: 512)
    let crown = NSBezierPath(); crown.appendArc(withCenter: center, radius: 276, startAngle: 40, endAngle: 140)
    crown.lineWidth = 90; crown.lineCapStyle = .butt; orange.setStroke(); crown.stroke()
    let ring = NSBezierPath(); ring.appendArc(withCenter: center, radius: 276, startAngle: 151, endAngle: 389)
    ring.lineWidth = 90; ring.lineCapStyle = .butt; silver.setStroke(); ring.stroke()
    silver.setFill()
    for direction in [-1.0, 1.0] {
        let arm = NSBezierPath()
        arm.move(to: NSPoint(x: 512 + direction * 34, y: 690))
        arm.line(to: NSPoint(x: 512 + direction * 34, y: 525))
        arm.line(to: NSPoint(x: 512 + direction * 233, y: 347))
        arm.line(to: NSPoint(x: 512 + direction * 165, y: 282))
        arm.line(to: NSPoint(x: 512, y: 432))
        arm.line(to: NSPoint(x: 512, y: 650))
        arm.close(); arm.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
}
