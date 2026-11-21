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
print("ok")
