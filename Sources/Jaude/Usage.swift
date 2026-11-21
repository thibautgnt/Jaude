import Foundation

struct Usage: Decodable {
    var limits: [Limit]
    var spend: Spend?

    enum CodingKeys: CodingKey { case limits, spend }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        limits = try c.decodeIfPresent([Limit].self, forKey: .limits) ?? []
        // The spend block changes shape often; never let it break the limits.
        spend = try? c.decodeIfPresent(Spend.self, forKey: .spend)
    }

    /// Share of the allowance still available, 0...1; 0 when the limit is absent.
    func remaining(_ kind: String) -> Double {
        guard let used = limits.first(where: { $0.kind == kind })?.percent else { return 0 }
        return min(max(1 - used / 100, 0), 1)
    }

    static func decode(_ data: Data) throws -> Usage {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(Usage.self, from: data)
    }
}

struct Limit: Decodable, Identifiable {
    var kind: String
    var percent: Double
    var severity: String?
    var resetsAt: String?
    var scope: Scope?

    struct Scope: Decodable {
        var model: Model?
        struct Model: Decodable { var displayName: String? }
    }

    var id: String { kind + (scope?.model?.displayName ?? "") }

    var title: String {
        switch kind {
        case "session": "Session"
        case "weekly_all": "Week"
        case "weekly_scoped": "Week · \(scope?.model?.displayName ?? "scoped")"
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    enum Pace { case fine, fast, critical }

    /// Compares usage with the time elapsed in the window: using more than the elapsed share means the limit runs out before it resets.
    func pace(now: Date = .now) -> Pace {
        let used = percent / 100
        if used >= 0.9 || (severity ?? "normal") != "normal" && used >= 0.75 { return .critical }
        var projected = 0.0
        if let reset = resetDate, let window {
            let elapsed = 1 - reset.timeIntervalSince(now) / window
            // Too early in the window, the projection is noise.
            if elapsed >= 0.1 { projected = used / elapsed }
        }
        if projected >= 1.5 { return .critical }
        if used >= 0.75 || projected >= 1 || (severity ?? "normal") != "normal" { return .fast }
        return .fine
    }

    private var window: TimeInterval? {
        if kind == "session" { return 5 * 3600 }
        if kind.hasPrefix("weekly") { return 7 * 86_400 }
        return nil
    }

    var resetDate: Date? {
        guard let s = resetsAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

struct Spend: Decodable {
    var enabled: Bool
    var used: Money?
    var limit: Money?

    struct Money: Decodable {
        var amountMinor: Int
        var currency: String
        var exponent: Int

        var formatted: String {
            (Double(amountMinor) / pow(10, Double(exponent))).formatted(.currency(code: currency))
        }
    }
}

enum UsageError: LocalizedError {
    case noCredentials, expired, rateLimited, http(Int)

    var errorDescription: String? {
        switch self {
        case .noCredentials: "Claude Code credentials not found. Log in with `claude` first."
        case .expired: "Token expired. Open Claude Code to refresh it."
        case .rateLimited: "Rate limited, will retry later."
        case .http(let code): "Server error (HTTP \(code))."
        }
    }
}

@MainActor
enum UsageAPI {
    // Going through /usr/bin/security reuses the keychain access Claude Code already granted, so no prompt.
    static func token() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        struct Creds: Decodable {
            struct OAuth: Decodable { var accessToken: String }
            var claudeAiOauth: OAuth
        }
        guard p.terminationStatus == 0,
              let creds = try? JSONDecoder().decode(Creds.self, from: data)
        else { throw UsageError.noCredentials }
        return creds.claudeAiOauth.accessToken
    }

    private static var cachedToken: String?

    static func fetch() async throws -> Usage {
        let cached = cachedToken
        var (data, status) = try await get(cached ?? token())
        // Claude Code rotates the token: re-read the keychain only when the cached one is refused.
        if status == 401, cached != nil { (data, status) = try await get(token()) }
        switch status {
        case 200: return try Usage.decode(data)
        case 401:
            cachedToken = nil
            throw UsageError.expired
        case 429: throw UsageError.rateLimited
        case let code: throw UsageError.http(code)
        }
    }

    private static func get(_ token: String) async throws -> (Data, Int) {
        cachedToken = token
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
