import XCTest
import SwiftUI
@testable import Notchless

/// Label/color for every `PaceStatus`, mirroring the fixed-clock convention in
/// `GoalStoreTests` so pace math never depends on the real date.
@MainActor
final class GoalPacePresentationTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
    private func days(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

    private func goal(_ current: Decimal) -> Goal {
        Goal(name: "g", target: 100_000, startDate: t0, deadline: days(100),
             contributions: current == 0 ? [] : [Contribution(amount: current, label: "a", date: t0)])
    }

    func test_onTrack() {
        let g = goal(50_000)
        XCTAssertEqual(GoalPacePresentation.label(for: g, now: days(50), symbol: "₵"), "On track")
        XCTAssertEqual(GoalPacePresentation.color(for: g, now: days(50)), NotchTheme.positive)
    }

    func test_ahead() {
        let g = goal(53_000)
        XCTAssertEqual(GoalPacePresentation.label(for: g, now: days(50), symbol: "₵"), "Ahead 3k ₵")
        XCTAssertEqual(GoalPacePresentation.color(for: g, now: days(50)), NotchTheme.positive)
    }

    func test_behind() {
        let g = goal(40_000)
        XCTAssertEqual(GoalPacePresentation.label(for: g, now: days(50), symbol: "₵"), "Behind 10k ₵")
        XCTAssertEqual(GoalPacePresentation.color(for: g, now: days(50)), NotchTheme.warning)
    }

    func test_overdue() {
        let g = goal(90_000)
        XCTAssertEqual(GoalPacePresentation.label(for: g, now: days(101), symbol: "₵"), "Overdue")
        XCTAssertEqual(GoalPacePresentation.color(for: g, now: days(101)), NotchTheme.warning)
    }
}
