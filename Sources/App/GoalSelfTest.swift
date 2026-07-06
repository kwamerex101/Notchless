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
        paceChecks()
        formatChecks()
        storeChecks()

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

    private static func paceChecks() {
        // target 100k over 100 days; halfway ⇒ expected 50k.
        func goal(_ current: Decimal) -> Goal {
            Goal(name: "g", target: 100_000, startDate: t0, deadline: days(100),
                 contributions: current == 0 ? [] : [Contribution(amount: current, label: "a", date: t0)])
        }
        check("pace on-track at expected", goal(50_000).pace(now: days(50)) == .onTrack)
        check("pace within dead-band is on-track", goal(51_000).pace(now: days(50)) == .onTrack)
        check("pace ahead past dead-band", goal(53_000).pace(now: days(50)) == .ahead(3_000))
        check("pace behind past dead-band", goal(40_000).pace(now: days(50)) == .behind(10_000))
        check("pace overdue when past deadline unmet", goal(90_000).pace(now: days(101)) == .overdue)
        check("pace not overdue when target met", goal(100_000).pace(now: days(101)) == .onTrack)
    }

    private static func formatChecks() {
        check("format groups thousands", goalFormatAmount(42_000, symbol: "₵") == "42,000 ₵")
        check("format handles small", goalFormatAmount(250, symbol: "₵") == "250 ₵")
        check("abbrev k whole", goalAbbreviate(100_000, symbol: "₵") == "100k ₵")
        check("abbrev k decimal", goalAbbreviate(1_500, symbol: "₵") == "1.5k ₵")
        check("abbrev under 1000", goalAbbreviate(250, symbol: "₵") == "250 ₵")
        check("abbrev millions", goalAbbreviate(1_200_000, symbol: "₵") == "1.2m ₵")
    }

    private static func storeChecks() {
        let suite = "goal.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = GoalStore(defaults: defaults, mirrorsICloud: false)

        // add validation
        check("addGoal rejects empty name", store.addGoal(name: " ", target: 100, deadline: days(10), startDate: t0) == nil)
        check("addGoal rejects non-positive target", store.addGoal(name: "x", target: 0, deadline: days(10), startDate: t0) == nil)
        check("addGoal rejects bad deadline", store.addGoal(name: "x", target: 100, deadline: t0, startDate: t0) == nil)

        guard let g = store.addGoal(name: "Save", target: 100, deadline: days(10), startDate: t0) else {
            check("addGoal succeeds", false); return
        }
        check("addGoal succeeds", store.goals.count == 1)
        check("first goal auto-pins", store.pinnedID == g.id)

        // log validation + sum
        check("log rejects zero", store.logContribution(goalID: g.id, amount: 0, label: "a", date: t0) == false)
        check("log rejects blank label", store.logContribution(goalID: g.id, amount: 10, label: " ", date: t0) == false)
        _ = store.logContribution(goalID: g.id, amount: 40, label: "MTN", date: t0)
        check("log adds to current", store.goals.first?.current == 40)

        // completion → archive + repin
        let g2 = store.addGoal(name: "Second", target: 50, deadline: days(10), startDate: t0)!
        _ = store.logContribution(goalID: g.id, amount: 60, label: "MTN", date: t0) // reaches 100
        check("reaching target archives goal", store.completed.contains { $0.id == g.id })
        check("completed goal leaves active list", store.goals.contains { $0.id == g.id } == false)
        check("pin moves to next active goal", store.pinnedID == g2.id)

        // persistence round-trip
        let reloaded = GoalStore(defaults: defaults, mirrorsICloud: false)
        check("goals persist across reload", reloaded.goals.contains { $0.id == g2.id })
        check("completed persist across reload", reloaded.completed.contains { $0.id == g.id })

        // corrupt data ⇒ empty, no crash
        defaults.set(Data("nonsense".utf8), forKey: "goals.store.v1")
        let corrupt = GoalStore(defaults: defaults, mirrorsICloud: false)
        check("corrupt data falls back to empty", corrupt.goals.isEmpty && corrupt.completed.isEmpty)
    }
}
