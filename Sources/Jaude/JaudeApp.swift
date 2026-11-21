import AppKit
import SwiftUI

@main
struct JaudeApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            Image(nsImage: gauge(session: store.remaining("session"), week: store.remaining("weekly_all")))
        }
        .menuBarExtraStyle(.window)
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

    // No data yet stays empty rather than pretending everything is left.
    func remaining(_ kind: String) -> Double {
        guard let used = usage?.limits.first(where: { $0.kind == kind })?.percent else { return 0 }
        return 1 - used / 100
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

struct Panel: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = store.error {
                Text(error).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(store.usage?.limits ?? []) { LimitRow(limit: $0) }
            if let spend = store.usage?.spend, spend.enabled, let used = spend.used {
                HStack {
                    Text("Usage credits").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(spend.limit.map { "\(used.formatted) / \($0.formatted)" } ?? used.formatted)
                        .monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                if let updated = store.updated {
                    Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("Quit")
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 260)
        .task { await store.refreshIfStale() }
    }
}

struct LimitRow: View {
    let limit: Limit
    private var left: Double { min(max(100 - limit.percent, 0), 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int(left.rounded())) % left").monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: left, total: 100)
                .tint(limit.percent >= 100 ? .red : limit.severity == "normal" ? .accentColor : .orange)
            if let reset = limit.resetDate {
                Text("Resets \(resetText(reset))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func resetText(_ date: Date) -> String {
        date.timeIntervalSinceNow < 86_400
            ? date.formatted(.relative(presentation: .named))
            : date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}
