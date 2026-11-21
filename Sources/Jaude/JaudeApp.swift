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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: Panel(store: store))

        iconUpdates = store.$usage.combineLatest(store.$iconStyle).sink { [weak self] usage, style in
            self?.statusItem.button?.image = style.image(
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
    @Published var iconStyle = IconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .bars {
        didSet { UserDefaults.standard.set(iconStyle.rawValue, forKey: "iconStyle") }
    }

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
            iconMenu
            glassButton("arrow.clockwise", help: "Refresh") { Task { await store.refresh() } }
            glassButton("power", help: "Quit Jaude") { NSApp.terminate(nil) }
        }
    }

    private var iconMenu: some View {
        Menu {
            Picker("Menu bar icon", selection: $store.iconStyle) {
                ForEach(IconStyle.allCases) { style in
                    Label {
                        Text(style.title)
                    } icon: {
                        Image(nsImage: style.image(session: 0.7, week: 0.4))
                    }
                    .tag(style)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .padding(4)
                .glassControl()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Menu bar icon")
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
