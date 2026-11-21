// Renders the 1024 px app icon: `swift Icon/render.swift out.png`.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824 px body centred in the 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.addPath(shape)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor(srgbRed: 0.33, green: 0.56, blue: 1.00, alpha: 1).cgColor,
    NSColor(srgbRed: 0.10, green: 0.22, blue: 0.70, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor,
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
ctx.restoreGState()

let c = CGPoint(x: 512, y: 512)
let white = NSColor.white

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.25).cgColor)

// Weekly ring: track, then three quarters left.
ctx.setLineWidth(54)
ctx.setLineCap(.round)
ctx.setStrokeColor(white.withAlphaComponent(0.22).cgColor)
ctx.addEllipse(in: CGRect(x: c.x - 282, y: c.y - 282, width: 564, height: 564))
ctx.strokePath()
ctx.setStrokeColor(white.cgColor)
ctx.addArc(center: c, radius: 282, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * 0.72, clockwise: true)
ctx.strokePath()
ctx.restoreGState()

// Session disc: faint track, then a liquid level with a gentle wave.
let inner = CGRect(x: c.x - 196, y: c.y - 196, width: 392, height: 392)
ctx.setFillColor(white.withAlphaComponent(0.16).cgColor)
ctx.fillEllipse(in: inner)
ctx.saveGState()
ctx.addEllipse(in: inner)
ctx.clip()
let level = inner.minY + inner.height * 0.58
let wave = CGMutablePath()
wave.move(to: CGPoint(x: inner.minX - 10, y: inner.minY - 10))
wave.addLine(to: CGPoint(x: inner.minX - 10, y: level))
stride(from: inner.minX - 10, through: inner.maxX + 10, by: 4).forEach { x in
    wave.addLine(to: CGPoint(x: x, y: level + 14 * sin((x - inner.minX) / inner.width * 2 * .pi)))
}
wave.addLine(to: CGPoint(x: inner.maxX + 10, y: inner.minY - 10))
wave.closeSubpath()
ctx.addPath(wave)
ctx.setFillColor(white.cgColor)
ctx.fillPath()
ctx.restoreGState()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
