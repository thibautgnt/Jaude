import Foundation

let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
let usage = try Usage.decode(Data(contentsOf: fixture))
assert(usage.limits.map(\.title) == ["Session", "Week", "Week · Fable"])
assert(usage.limits[0].percent == 4)
assert(usage.limits[0].resetDate != nil, "fractional seconds")
assert(usage.limits[2].resetDate != nil, "no fractional seconds")
assert(usage.spend?.enabled == false)
assert(abs(usage.remaining("session") - 0.96) < 1e-9)
assert(usage.remaining("missing") == 0)
func limit(_ kind: String, _ percent: Double, resetIn: TimeInterval) -> Limit {
    let reset = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(resetIn))
    return Limit(kind: kind, percent: percent, severity: "normal", resetsAt: reset, scope: nil)
}
let hour: TimeInterval = 3600
assert(limit("session", 30, resetIn: 2.5 * hour).pace() == .fine)      // 30 % used, half the window gone
assert(limit("session", 60, resetIn: 2.5 * hour).pace() == .fast)      // on track to run out before reset
assert(limit("session", 90, resetIn: 4 * hour).pace() == .critical)
assert(limit("session", 10, resetIn: 4.9 * hour).pace() == .fine)      // too early to project
assert(limit("weekly_all", 50, resetIn: 6 * 24 * hour).pace() == .critical) // half the week gone in a day
assert(limit("weekly_all", 40, resetIn: 3 * 24 * hour).pace() == .fine)
print("ok")
