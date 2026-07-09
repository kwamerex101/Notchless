import XCTest
@testable import Notchless

final class ScrollDetentAccumulatorTests: XCTestCase {
    // base 24, +0.02 px threshold per px/s, fling >6000 px/s, gap 0.25s
    private var acc = ScrollDetentAccumulator(tuning: DetentTuning())

    func test_slowScroll_accumulatesToOneTick() {
        // v=0 → th=24; then v=100 → th=26.
        XCTAssertEqual(acc.ticks(delta: 10, timestamp: 0.0), 0)   // acc 10
        XCTAssertEqual(acc.ticks(delta: 10, timestamp: 0.1), 0)   // acc 20
        XCTAssertEqual(acc.ticks(delta: 10, timestamp: 0.2), 1)   // acc 30 ≥ 26 → 1, rem 4
    }

    func test_bigFirstDelta_yieldsMultipleTicks() {
        // First event: velocity 0 → threshold 24. 100/24 = 4 ticks, rem 4.
        XCTAssertEqual(acc.ticks(delta: 100, timestamp: 0.0), 4)
    }

    func test_directionChange_resetsAccumulation() {
        XCTAssertEqual(acc.ticks(delta: 20, timestamp: 0.0), 0)    // up: acc 20
        XCTAssertEqual(acc.ticks(delta: -20, timestamp: 0.1), 0)   // flip: reset → acc 20 (th 24+4=28 at v=200)
        XCTAssertEqual(acc.ticks(delta: -10, timestamp: 0.2), 1)   // acc 30 ≥ 26 (v=100) → 1
    }

    func test_fasterScroll_widensSpacing() {
        // Same 60px total; fast gets fewer ticks than slow.
        var slow = ScrollDetentAccumulator(tuning: DetentTuning())
        var fast = ScrollDetentAccumulator(tuning: DetentTuning())
        var slowTicks = 0, fastTicks = 0
        for i in 1...6 { slowTicks += slow.ticks(delta: 10, timestamp: Double(i) * 0.1) }    // v=100 → th 26
        for i in 1...6 { fastTicks += fast.ticks(delta: 10, timestamp: Double(i) * 0.005) }  // v=2000 → th 64
        XCTAssertEqual(slowTicks, 2)   // 60/26
        XCTAssertEqual(fastTicks, 0)   // 60 < 64
    }

    func test_fling_suppressesAndResets() {
        XCTAssertEqual(acc.ticks(delta: 20, timestamp: 0.0), 0)                 // acc 20
        XCTAssertEqual(acc.ticks(delta: 300, timestamp: 0.03), 0)               // v=10000 > 6000 → suppress + reset
        XCTAssertEqual(acc.ticks(delta: 10, timestamp: 0.13), 0)                // fresh: acc 10, not 330
        XCTAssertEqual(acc.ticks(delta: 20, timestamp: 0.23), 1)                // acc 30 ≥ 28 (v=200) → 1
    }

    func test_gestureGap_resetsAccumulation() {
        XCTAssertEqual(acc.ticks(delta: 20, timestamp: 0.0), 0)    // acc 20
        // 2s later: new gesture. Without reset, 20+20=40 ≥ 24 would tick.
        XCTAssertEqual(acc.ticks(delta: 20, timestamp: 2.0), 0)    // reset → acc 20
    }

    func test_zeroDelta_isIgnored() {
        XCTAssertEqual(acc.ticks(delta: 0, timestamp: 0.0), 0)
        XCTAssertEqual(acc.ticks(delta: 30, timestamp: 0.1), 1)    // first real event, th 24
    }

    func test_reset_clearsState() {
        _ = acc.ticks(delta: 20, timestamp: 0.0)
        acc.reset()
        XCTAssertEqual(acc.ticks(delta: 20, timestamp: 0.1), 0)    // fresh accumulation
    }
}
