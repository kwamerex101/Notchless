import Foundation

/// Dev-only deterministic assertions for Goal math and GoalStore behavior.
/// Runs only when DI_GOAL_SELFTEST is set (mirrors DI_DEBUG_RENDER), prints one
/// PASS/FAIL line per check, then exits so it is scriptable from the CLI.
@MainActor
enum GoalSelfTest {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["DI_GOAL_SELFTEST"] != nil }

    private static var failures = 0

    private static func check(_ name: String, _ condition: Bool) {
        if condition { print("PASS \(name)") }
        else { print("FAIL \(name)"); failures += 1 }
    }

    // Fixed clock so nothing depends on the real date.
    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
    private static func days(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

    static func run() {
        guard isEnabled else { return }

        modelChecks()
        // Later tasks append: paceChecks(); formatChecks(); storeChecks()

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }

    private static func modelChecks() {
        let g = Goal(name: "Save", target: 100_000, startDate: t0, deadline: days(100),
                     contributions: [
                        Contribution(amount: 25_000, label: "MTN stocks", date: t0),
                        Contribution(amount: 12_000, label: "Petra", date: t0),
                        Contribution(amount: 5_000, label: "MTN stocks", date: t0),
                     ])
        check("current sums contributions", g.current == 42_000)
        check("percent rounds fraction", g.percent == 42)
        let bd = g.breakdown
        check("breakdown groups by label", bd.count == 2)
        check("breakdown sorts largest first", bd.first?.label == "MTN stocks" && bd.first?.total == 30_000)

        let over = Goal(name: "x", target: 100, startDate: t0, deadline: days(1),
                        contributions: [Contribution(amount: 150, label: "a", date: t0)])
        check("fraction clamps at 1", over.fraction == 1.0)
        let zero = Goal(name: "z", target: 0, startDate: t0, deadline: days(1))
        check("fraction is 0 for non-positive target", zero.fraction == 0)
    }
}
