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

    static func fetch() async throws -> Usage {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: req)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return try Usage.decode(data)
        case 401: throw UsageError.expired
        case 429: throw UsageError.rateLimited
        case let code: throw UsageError.http(code)
        }
    }
}
