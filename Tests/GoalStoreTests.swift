import XCTest
@testable import Notchless

/// Goal math + GoalStore behavior, ported from the env-gated GoalSelfTest into
/// real XCTest so it runs in `xcodebuild test`, plus the previously-uncovered
/// catch-up-rate math (neededPerMonth / monthsRemaining).
@MainActor
final class GoalStoreTests: XCTestCase {
    // Fixed clock so nothing depends on the real date.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
    private func days(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

    // MARK: Model

    func test_currentPercentBreakdown() {
        let g = Goal(name: "Save", target: 100_000, startDate: t0, deadline: days(100),
                     contributions: [
                        Contribution(amount: 25_000, label: "MTN stocks", date: t0),
                        Contribution(amount: 12_000, label: "Petra", date: t0),
                        Contribution(amount: 5_000, label: "MTN stocks", date: t0),
                     ])
        XCTAssertEqual(g.current, 42_000)
        XCTAssertEqual(g.percent, 42)
        let bd = g.breakdown
        XCTAssertEqual(bd.count, 2)
        XCTAssertEqual(bd.first?.label, "MTN stocks")
        XCTAssertEqual(bd.first?.total, 30_000)
    }

    func test_fractionClampsAndGuardsZeroTarget() {
        let over = Goal(name: "x", target: 100, startDate: t0, deadline: days(1),
                        contributions: [Contribution(amount: 150, label: "a", date: t0)])
        XCTAssertEqual(over.fraction, 1.0)
        let zero = Goal(name: "z", target: 0, startDate: t0, deadline: days(1))
        XCTAssertEqual(zero.fraction, 0)
    }

    // MARK: Pace

    private func goal(_ current: Decimal) -> Goal {
        Goal(name: "g", target: 100_000, startDate: t0, deadline: days(100),
             contributions: current == 0 ? [] : [Contribution(amount: current, label: "a", date: t0)])
    }

    func test_pace() {
        XCTAssertEqual(goal(50_000).pace(now: days(50)), .onTrack)
        XCTAssertEqual(goal(51_000).pace(now: days(50)), .onTrack)      // within 2% dead-band
        XCTAssertEqual(goal(53_000).pace(now: days(50)), .ahead(3_000))
        XCTAssertEqual(goal(40_000).pace(now: days(50)), .behind(10_000))
        XCTAssertEqual(goal(90_000).pace(now: days(101)), .overdue)
        XCTAssertEqual(goal(100_000).pace(now: days(101)), .onTrack)    // met → not overdue
    }

    // MARK: Catch-up rate (previously untested)

    func test_monthsRemaining_clampsAtZeroPastDeadline() {
        XCTAssertEqual(goal(0).monthsRemaining(now: days(200)), 0)  // deadline passed → 0, not negative
        XCTAssertGreaterThan(goal(0).monthsRemaining(now: t0), 3)   // ~100 days ≈ 3.3 months
    }

    func test_neededPerMonth_nilWhenTargetMet() {
        XCTAssertNil(goal(100_000).neededPerMonth(now: t0))
        XCTAssertNil(goal(120_000).neededPerMonth(now: t0))
    }

    func test_neededPerMonth_usesMonthFloorNearDeadline() {
        // Deadline passed, target unmet: months floors to 1, so it returns the
        // full remaining amount (never divides by ~0 / explodes).
        let need = goal(30_000).neededPerMonth(now: days(200))
        XCTAssertEqual(need, 70_000)
    }

    func test_neededPerMonth_linearWhenOnPace() {
        // 100k target, 50k saved, ~3.3 months left → ~15k/mo. Just assert it's
        // a sane positive figure well under the full remaining.
        let need = goal(50_000).neededPerMonth(now: t0)
        XCTAssertNotNil(need)
        if let need { XCTAssertGreaterThan(need, 10_000); XCTAssertLessThan(need, 50_000) }
    }

    // MARK: Formatting

    func test_formatting() {
        XCTAssertEqual(goalFormatAmount(42_000, symbol: "₵"), "42,000 ₵")
        XCTAssertEqual(goalFormatAmount(250, symbol: "₵"), "250 ₵")
        XCTAssertEqual(goalAbbreviate(100_000, symbol: "₵"), "100k ₵")
        XCTAssertEqual(goalAbbreviate(1_500, symbol: "₵"), "1.5k ₵")
        XCTAssertEqual(goalAbbreviate(250, symbol: "₵"), "250 ₵")
        XCTAssertEqual(goalAbbreviate(1_200_000, symbol: "₵"), "1.2m ₵")
    }

    // MARK: Store

    private func makeStore() -> (GoalStore, UserDefaults, String) {
        let suite = "goal.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (GoalStore(defaults: defaults, mirrorsICloud: false), defaults, suite)
    }

    func test_addGoalValidationAndAutoPin() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(store.addGoal(name: " ", target: 100, deadline: days(10), startDate: t0))
        XCTAssertNil(store.addGoal(name: "x", target: 0, deadline: days(10), startDate: t0))
        XCTAssertNil(store.addGoal(name: "x", target: 100, deadline: t0, startDate: t0))
        let g = store.addGoal(name: "Save", target: 100, deadline: days(10), startDate: t0)
        XCTAssertNotNil(g)
        XCTAssertEqual(store.goals.count, 1)
        XCTAssertEqual(store.pinnedID, g?.id)
    }

    func test_logValidationArchiveAndRepin() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let g = store.addGoal(name: "Save", target: 100, deadline: days(10), startDate: t0)!
        XCTAssertFalse(store.logContribution(goalID: g.id, amount: 0, label: "a", date: t0))
        XCTAssertFalse(store.logContribution(goalID: g.id, amount: 10, label: " ", date: t0))
        XCTAssertTrue(store.logContribution(goalID: g.id, amount: 40, label: "MTN", date: t0))
        XCTAssertEqual(store.goals.first?.current, 40)

        let g2 = store.addGoal(name: "Second", target: 50, deadline: days(10), startDate: t0)!
        _ = store.logContribution(goalID: g.id, amount: 60, label: "MTN", date: t0)  // reaches 100
        XCTAssertTrue(store.completed.contains { $0.id == g.id })
        XCTAssertFalse(store.goals.contains { $0.id == g.id })
        XCTAssertEqual(store.pinnedID, g2.id)
    }

    func test_persistenceRoundTripAndCorruptRecovery() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let g = store.addGoal(name: "Save", target: 100, deadline: days(10), startDate: t0)!
        _ = store.logContribution(goalID: g.id, amount: 100, label: "MTN", date: t0)  // archive it

        let reloaded = GoalStore(defaults: defaults, mirrorsICloud: false)
        XCTAssertTrue(reloaded.completed.contains { $0.id == g.id })

        defaults.set(Data("nonsense".utf8), forKey: "goals.store.v1")
        let corrupt = GoalStore(defaults: defaults, mirrorsICloud: false)
        XCTAssertTrue(corrupt.goals.isEmpty && corrupt.completed.isEmpty)
    }
}
