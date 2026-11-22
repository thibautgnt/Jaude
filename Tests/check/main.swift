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
let line = Data(#"{"type":"assistant","timestamp":"2026-11-22T15:08:18.099Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":100000,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":1000000,"cache_creation":{"ephemeral_1h_input_tokens":1000000,"ephemeral_5m_input_tokens":0}}}}"#.utf8)
let reply = Pricing.reply(line)!
assert(reply.key == "msg_1|req_1")
assert(reply.reply.tokens == 3_100_000)
assert(abs(reply.reply.cost - (4 + 2 + 0.2 + 8)) < 1e-9)   // input + output + read + 1 h write at 2x
var scoped = limit("weekly_scoped", 10, resetIn: 24 * hour)
scoped.scope = .init(model: .init(displayName: "Fable"))
let replies = [Reply(date: .now, model: "claude-fable-5-2", tokens: 10, cost: 1), Reply(date: .now, model: "claude-opus-5-5", tokens: 5, cost: 2),
               Reply(date: .now.addingTimeInterval(-8 * 24 * hour), model: "claude-opus-5-5", tokens: 99, cost: 9)]
assert(scoped.tally(replies) == Tally(tokens: 10, cost: 1, models: ["claude-fable-5-2": 10]))
let all = limit("weekly_all", 10, resetIn: 24 * hour).tally(replies)!
assert(all == Tally(tokens: 15, cost: 3, models: ["claude-fable-5-2": 10, "claude-opus-5-5": 5]))
assert(all.modelsText == "Fable 5.2 67% · Opus 5.5 33%")
assert(Tally.name("claude-sonnet-4-5-20250929") == "Sonnet 4.5")
print("ok")
