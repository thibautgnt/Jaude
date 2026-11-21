import AppKit
import Combine
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var iconUpdates: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: Panel(store: store))

        iconUpdates = store.$usage.sink { [weak self] usage in
            self?.statusItem.button?.image = gauge(
                session: usage?.remaining("session") ?? 0,
                week: usage?.remaining("weekly_all") ?? 0
            )
        }
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            Task { await store.refreshIfStale() }
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var usage: Usage?
    @Published var error: String?
    @Published var updated: Date?

    init() {
        Task {
            while true {
                await refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func refresh() async {
        do {
            usage = try await UsageAPI.fetch()
            updated = .now
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshIfStale() async {
        if updated.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true { await refresh() }
    }
}

/// Outer ring = weekly allowance left, inner disc = session allowance left.
func gauge(session: Double, week: Double) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        let c = NSPoint(x: rect.midX, y: rect.midY)

        func arc(_ radius: CGFloat, _ fraction: Double, pie: Bool) -> NSBezierPath {
            let p = NSBezierPath()
            if pie { p.move(to: c) }
            p.appendArc(withCenter: c, radius: radius, startAngle: 90,
                        endAngle: 90 - 360 * min(max(fraction, 0), 1), clockwise: true)
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
            let ring = arc(6.75, week, pie: false)
            ring.lineWidth = 1.5
            ring.lineCapStyle = .round
            ring.stroke()
        }
        if session > 0 { arc(4.5, session, pie: true).fill() }
        return true
    }
    image.isTemplate = true
    return image
}

// Liquid Glass is for controls only; content sits on a matte surface so highlights never cross the text.
extension View {
    func contentSurface(radius: CGFloat = 12) -> some View {
        background(.white.opacity(0.06), in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
    }

    func glassControl(radius: CGFloat = 7) -> some View {
        glassEffect(.regular.tint(.black.opacity(0.2)).interactive(), in: .rect(cornerRadius: radius, style: .continuous))
    }
}

struct Panel: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(store.usage?.limits ?? []) { LimitCard(limit: $0) }
            if let spend = store.usage?.spend, spend.enabled, let used = spend.used {
                HStack {
                    Text("Usage credits").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(spend.limit.map { "\(used.formatted) / \($0.formatted)" } ?? used.formatted)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .contentSurface()
            }
            footer
        }
        .padding(14)
        .frame(width: 300)
        // Scrim under the glass so contrast holds over a light desktop.
        .background(.black.opacity(0.25))
    }

    private var footer: some View {
        HStack {
            if let error = store.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(2)
            } else if let updated = store.updated {
                Text(updated, format: .relative(presentation: .named))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            glassButton("arrow.clockwise", help: "Refresh") { Task { await store.refresh() } }
            glassButton("power", help: "Quit Jaude") { NSApp.terminate(nil) }
        }
    }

    private func glassButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .padding(4)
                .glassControl()
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct LimitCard: View {
    let limit: Limit
    private var left: Double { min(max(100 - limit.percent, 0), 100) }
    private var color: Color { left == 0 ? .red : limit.severity == "normal" ? .accentColor : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(left.rounded())) %")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("left").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: geo.size.width * left / 100)
                    }
            }
            .frame(height: 6)
            if let reset = limit.resetDate {
                Label("Resets \(resetText(reset))", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .contentSurface()
    }

    private func resetText(_ date: Date) -> String {
        date.timeIntervalSinceNow < 86_400
            ? date.formatted(.relative(presentation: .named))
            : date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}
