import Foundation

/// One Claude Code reply, read from the transcripts it writes in ~/.claude/projects.
struct Reply {
    var date: Date
    var model: String
    var tokens: Int
    var cost: Double
}

struct Tally: Equatable {
    var tokens = 0
    var cost = 0.0

    var text: String {
        let t = tokens.formatted(.number.notation(.compactName).precision(.significantDigits(2)))
        return "\(t) tokens · ~\(cost.formatted(.currency(code: "USD").precision(.fractionLength(2))))"
    }
}

enum Pricing {
    /// Dollars per million tokens: input, output, cache read. Cache writes are 1.25x input (5 min) and 2x (1 h).
    // shortcut: current-generation list prices by family, older versions priced like the current one; update when prices change.
    static func rates(_ model: String) -> (input: Double, output: Double, cacheRead: Double)? {
        if model.contains("fable") || model.contains("mythos") { return (8, 40, 0.20) }
        if model.contains("opus") { return (4, 20, 0.20) }
        if model.contains("sonnet") { return (2, 10, 0.10) }
        if model.contains("haiku") { return (0.10, 0.50, 0.01) }
        return nil
    }

    static func reply(_ line: Data) -> (key: String, reply: Reply)? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              o["type"] as? String == "assistant",
              let message = o["message"] as? [String: Any],
              let model = message["model"] as? String,
              let usage = message["usage"] as? [String: Any],
              let stamp = o["timestamp"] as? String,
              let date = parseDate(stamp)
        else { return nil }
        func n(_ k: String, in d: [String: Any] = usage) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
        let input = n("input_tokens"), output = n("output_tokens"), read = n("cache_read_input_tokens")
        let written = n("cache_creation_input_tokens")
        let split = usage["cache_creation"] as? [String: Any] ?? [:]
        let hour = n("ephemeral_1h_input_tokens", in: split)
        let minutes = split.isEmpty ? written : n("ephemeral_5m_input_tokens", in: split)
        var cost = 0.0
        if let r = rates(model) {
            cost = (input * r.input + output * r.output + read * r.cacheRead
                + minutes * r.input * 1.25 + hour * r.input * 2) / 1_000_000
        }
        // Claude Code writes the same reply once per content block: the id pair dedupes them.
        let key = "\(message["id"] as? String ?? "")|\(o["requestId"] as? String ?? stamp)"
        return (key, Reply(date: date, model: model, tokens: Int(input + output + read + written), cost: cost))
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Re-reads only the transcripts that changed since the last scan.
actor TranscriptScanner {
    private var files: [URL: (modified: Date, replies: [String: Reply])] = [:]
    private let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")

    func replies(since start: Date) -> [Reply] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var seen = Set<URL>()
        for case let url as URL in walk where url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate,
                  modified >= start else { continue }
            seen.insert(url)
            if files[url]?.modified == modified { continue }
            files[url] = (modified, parse(url))
        }
        files = files.filter { seen.contains($0.key) }
        var unique: [String: Reply] = [:]
        for file in files.values { unique.merge(file.replies) { a, _ in a } }
        return unique.values.filter { $0.date >= start }
    }

    private func parse(_ url: URL) -> [String: Reply] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [:] }
        var out: [String: Reply] = [:]
        let marker = Data("\"usage\"".utf8)
        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: marker) != nil {
            if let r = Pricing.reply(Data(line)) { out[r.key] = r.reply }
        }
        return out
    }
}

extension Limit {
    var windowStart: Date? {
        guard let reset = resetDate, let window else { return nil }
        return reset.addingTimeInterval(-window)
    }

    func tally(_ replies: [Reply]) -> Tally? {
        guard let start = windowStart else { return nil }
        let model = scope?.model?.displayName?.lowercased()
        return replies.reduce(into: Tally()) { t, r in
            guard r.date >= start, model.map({ r.model.contains($0) }) ?? true else { return }
            t.tokens += r.tokens
            t.cost += r.cost
        }
    }
}
