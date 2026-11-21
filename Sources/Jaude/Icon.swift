import AppKit

/// Menu bar icon styles. Session and week are the share of allowance left, 0...1.
enum IconStyle: String, CaseIterable, Identifiable {
    case bars, level, battery, ring

    var id: Self { self }

    var title: String {
        switch self {
        case .bars: "Bars"
        case .level: "Level"
        case .battery: "Battery"
        case .ring: "Ring"
        }
    }

    func image(session: Double, week: Double) -> NSImage {
        let s = min(max(session, 0), 1), w = min(max(week, 0), 1)
        let width: CGFloat = switch self {
        case .bars: 18
        case .level: 16
        case .battery: 24
        case .ring: 16
        }
        let image = NSImage(size: NSSize(width: width, height: 16), flipped: false) { rect in
            switch self {
            case .bars:
                drawBar(NSRect(x: 1, y: 7.5, width: 16, height: 5), s)
                drawBar(NSRect(x: 1, y: 3.5, width: 16, height: 2), w)
            case .level:
                drawRing(rect, session: s, week: w, liquid: true)
            case .battery:
                drawBattery(min(s, w))
            case .ring:
                drawRing(rect, session: s, week: w, liquid: false)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

private func drawBar(_ r: NSRect, _ fraction: Double) {
    let radius = r.height / 2
    NSColor.black.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
    guard fraction > 0 else { return }
    var fill = r
    fill.size.width = max(r.width * fraction, r.height)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
}

// Battery shows the tighter of the two limits: that is the one that will block first.
private func drawBattery(_ fraction: Double) {
    let body = NSRect(x: 1, y: 3.5, width: 20, height: 9)
    let outline = NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
    outline.lineWidth = 1
    NSColor.black.withAlphaComponent(0.5).set()
    outline.stroke()
    NSBezierPath(roundedRect: NSRect(x: 21.5, y: 6.5, width: 1.5, height: 3), xRadius: 0.75, yRadius: 0.75).fill()
    guard fraction > 0 else { return }
    let inner = body.insetBy(dx: 2, dy: 2)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: inner.width * fraction, height: inner.height),
                 xRadius: 1.2, yRadius: 1.2).fill()
}

// Outer ring = week left. Inner disc = session left, as a pie or as a liquid level.
private func drawRing(_ rect: NSRect, session: Double, week: Double, liquid: Bool) {
    let c = NSPoint(x: rect.midX, y: rect.midY)

    func arc(_ radius: CGFloat, _ fraction: Double, pie: Bool) -> NSBezierPath {
        let p = NSBezierPath()
        if pie { p.move(to: c) }
        p.appendArc(withCenter: c, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        if pie { p.close() }
        return p
    }

    let track = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
    track.lineWidth = 1.5
    NSColor.black.withAlphaComponent(0.3).setStroke()
    track.stroke()
    NSColor.black.withAlphaComponent(0.15).setFill()
    NSBezierPath(ovalIn: rect.insetBy(dx: 3.5, dy: 3.5)).fill()

    NSColor.black.set()
    if week > 0 {
        let outer = arc(6.75, week, pie: false)
        outer.lineWidth = 1.5
        outer.lineCapStyle = .round
        outer.stroke()
    }
    guard session > 0 else { return }
    if liquid {
        let inner = rect.insetBy(dx: 3.5, dy: 3.5)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: inner).addClip()
        NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * session).fill()
        NSGraphicsContext.restoreGraphicsState()
    } else {
        arc(4.5, session, pie: true).fill()
    }
}
