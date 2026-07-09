import XCTest
@testable import Notchless

final class MultitouchGestureRecognizerTests: XCTestCase {
    func test_gestureTick_equatable() {
        XCTAssertEqual(GestureTick.swipe(.left), .swipe(.left))
        XCTAssertNotEqual(GestureTick.swipe(.left), .swipe(.right))
        XCTAssertNotEqual(GestureTick.pinch, .spread)
    }

    func test_fingerTouch_touchingConstant() {
        XCTAssertEqual(FingerTouch.touching, 4)
    }

    func test_gestureTuning_defaults() {
        let t = GestureTuning()
        XCTAssertEqual(t.gestureMinFingers, 3)
        XCTAssertEqual(t.swipeThreshold, 0.15, accuracy: 0.0001)
    }

    func test_config_gesturesOn_defaultsFalse() {
        // Existing call sites omit gesturesOn; it must default to false.
        let c = TrackpadFeedbackConfig(
            hapticsOn: true, soundOn: true, scrollOn: true, clickOn: true,
            strength: .medium, voiceID: "twig", volume: 0.5)
        XCTAssertFalse(c.gesturesOn)
    }
}

extension MultitouchGestureRecognizerTests {
    private func touches(_ pts: [(Double, Double)], state: Int = FingerTouch.touching) -> [FingerTouch] {
        pts.enumerated().map { FingerTouch(x: $0.element.0, y: $0.element.1, id: $0.offset, state: state) }
    }

    // Three fingers, centroid (0.35, 0.50).
    private var threeBase: [(Double, Double)] { [(0.30, 0.50), (0.35, 0.50), (0.40, 0.50)] }

    func test_swipeRight_firesOnce_thenLatches() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        XCTAssertNil(r.recognize(touches: touches(threeBase), timestamp: 0.0))   // peak→3, arming
        XCTAssertNil(r.recognize(touches: touches(threeBase), timestamp: 0.06))  // armed, baseline
        let right = threeBase.map { ($0.0 + 0.20, $0.1) }                        // dx=+0.20
        XCTAssertEqual(r.recognize(touches: touches(right), timestamp: 0.10), .swipe(.right))
        let more = threeBase.map { ($0.0 + 0.30, $0.1) }
        XCTAssertNil(r.recognize(touches: touches(more), timestamp: 0.14))       // latched
    }

    func test_swipeLeft() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.06)
        let left = threeBase.map { ($0.0 - 0.20, $0.1) }
        XCTAssertEqual(r.recognize(touches: touches(left), timestamp: 0.10), .swipe(.left))
    }

    func test_swipeUp_and_down() {
        var up = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = up.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = up.recognize(touches: touches(threeBase), timestamp: 0.06)
        XCTAssertEqual(up.recognize(touches: touches(threeBase.map { ($0.0, $0.1 + 0.20) }), timestamp: 0.10), .swipe(.up))

        var down = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = down.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = down.recognize(touches: touches(threeBase), timestamp: 0.06)
        XCTAssertEqual(down.recognize(touches: touches(threeBase.map { ($0.0, $0.1 - 0.20) }), timestamp: 0.10), .swipe(.down))
    }

    // Four fingers around centroid (0.50,0.50), mean radius 0.15.
    private var fourBase: [(Double, Double)] { [(0.35, 0.50), (0.65, 0.50), (0.50, 0.35), (0.50, 0.65)] }

    func test_fourFingerSpread() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(fourBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(fourBase), timestamp: 0.06)   // baseline radius 0.15
        let spread: [(Double, Double)] = [(0.20, 0.50), (0.80, 0.50), (0.50, 0.20), (0.50, 0.80)]  // radius 0.30, dr=+0.15
        XCTAssertEqual(r.recognize(touches: touches(spread), timestamp: 0.10), .spread)
    }

    func test_fourFingerPinch() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(fourBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(fourBase), timestamp: 0.06)
        let pinch: [(Double, Double)] = [(0.47, 0.50), (0.53, 0.50), (0.50, 0.47), (0.50, 0.53)]   // radius 0.03, dr=-0.12
        XCTAssertEqual(r.recognize(touches: touches(pinch), timestamp: 0.10), .pinch)
    }

    func test_settleWindow_landing3then4_firesOnce() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        let three = threeBase
        let four = three + [(0.45, 0.50)]
        XCTAssertNil(r.recognize(touches: touches(three), timestamp: 0.00))  // peak→3, stableSince 0
        XCTAssertNil(r.recognize(touches: touches(four), timestamp: 0.02))   // peak→4, stableSince 0.02
        XCTAssertNil(r.recognize(touches: touches(four), timestamp: 0.06))   // 0.04<0.05, not armed
        XCTAssertNil(r.recognize(touches: touches(four), timestamp: 0.08))   // 0.06>=0.05, armed
        let moved = four.map { ($0.0 + 0.20, $0.1) }
        XCTAssertEqual(r.recognize(touches: touches(moved), timestamp: 0.12), .swipe(.right))
    }

    func test_stateFilter_leavingTouchesNotCounted() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        // 2 touching + 1 leaving (state 7) → count 2 < 3 → nil (no arming).
        let mixed = touches([(0.30, 0.50), (0.35, 0.50)]) + touches([(0.40, 0.50)], state: 7)
        XCTAssertNil(r.recognize(touches: mixed, timestamp: 0.0))
        XCTAssertNil(r.recognize(touches: mixed, timestamp: 0.10))
    }

    func test_twoFingers_neverFire() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        XCTAssertNil(r.recognize(touches: touches([(0.3, 0.5), (0.5, 0.5)]), timestamp: 0.0))
        XCTAssertNil(r.recognize(touches: touches([(0.6, 0.5), (0.8, 0.5)]), timestamp: 0.1))  // big move, still 2
    }

    func test_subThreshold_noFire() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.06)
        let small = threeBase.map { ($0.0 + 0.10, $0.1) }  // dist 0.10 < 0.15
        XCTAssertNil(r.recognize(touches: touches(small), timestamp: 0.10))
    }

    func test_diagonalAmbiguous_noFire() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.06)
        let diag = threeBase.map { ($0.0 + 0.13, $0.1 + 0.13) }  // dist 0.184>=0.15, |dx|==|dy| → no dominance
        XCTAssertNil(r.recognize(touches: touches(diag), timestamp: 0.10))
    }

    // Competing pinch-vs-swipe tie-break: both `dist` and `dr` cross their
    // thresholds simultaneously (unlike test_fourFingerSpread/Pinch, which
    // hold the centroid stationary). Formula (MultitouchGestureRecognizer):
    //   swipeScore = dist / 0.15;  pinchScore = |dr| / 0.12
    //   pinch/spread wins iff peakCount>=4 && |dr|>=0.12 && pinchScore >= swipeScore
    //   else swipe wins iff dist>=0.15 && one axis dominates the other 1.5x

    // Base: 4 fingers, centroid (0.50,0.50), each at radius 0.15 from center
    // (offsets ±0.15 on each axis) — same shape as `fourBase`.
    private var tieBase: [(Double, Double)] { [(0.35, 0.50), (0.65, 0.50), (0.50, 0.35), (0.50, 0.65)] }

    func test_competingPinchVsSwipe_swipeDominant_firesSwipe() {
        // Move centroid dx=+0.30 (dy=0) and grow radius 0.15→0.27 (dr=+0.12).
        //   dist = 0.30 → swipeScore = 0.30/0.15 = 2.0
        //   dr   = 0.12 → pinchScore = 0.12/0.12 = 1.0
        // pinchScore (1.0) < swipeScore (2.0) → pinch condition
        // (|dr|/pinchThreshold >= swipeScore) is false → falls through to the
        // swipe check: dist(0.30) >= 0.15 and |dx|(0.30) >= 1.5*|dy|(0) → .swipe(.right).
        // New centroid (0.80,0.50); offsets scaled 0.15→0.27 (×1.8) from the
        // base ±0.15/0/0 pattern: (-0.27,0),(0.27,0),(0,-0.27),(0,0.27).
        let moved: [(Double, Double)] = [(0.53, 0.50), (1.07, 0.50), (0.80, 0.23), (0.80, 0.77)]
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(tieBase), timestamp: 0.0)   // peak→4, stableSince 0
        _ = r.recognize(touches: touches(tieBase), timestamp: 0.06)  // armed, baseline radius 0.15
        XCTAssertEqual(r.recognize(touches: touches(moved), timestamp: 0.10), .swipe(.right))
    }

    func test_competingPinchVsSwipe_pinchDominant_firesPinch() {
        // Custom base with a larger radius (0.30) so a big shrink stays
        // non-negative: centroid (0.50,0.50), offsets ±0.30 on each axis.
        // Move centroid dx=+0.18 (dy=0) and shrink radius 0.30→0.06 (dr=-0.24).
        //   dist = 0.18 → swipeScore = 0.18/0.15 = 1.2  (crosses swipe threshold too)
        //   dr   = -0.24 → pinchScore = 0.24/0.12 = 2.0
        // pinchScore (2.0) >= swipeScore (1.2) and |dr|(0.24) >= 0.12 → pinch
        // wins (dr<0 → .pinch) even though dist also cleared 0.15.
        let base: [(Double, Double)] = [(0.20, 0.50), (0.80, 0.50), (0.50, 0.20), (0.50, 0.80)]
        // New centroid (0.68,0.50); offsets scaled 0.30→0.06 (×0.2):
        // (-0.06,0),(0.06,0),(0,-0.06),(0,0.06).
        let moved: [(Double, Double)] = [(0.62, 0.50), (0.74, 0.50), (0.68, 0.44), (0.68, 0.56)]
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(base), timestamp: 0.0)   // peak→4, stableSince 0
        _ = r.recognize(touches: touches(base), timestamp: 0.06)  // armed, baseline radius 0.30
        XCTAssertEqual(r.recognize(touches: touches(moved), timestamp: 0.10), .pinch)
    }

    func test_resetAfterLift_allowsNewGesture() {
        var r = MultitouchGestureRecognizer(tuning: GestureTuning())
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.0)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.06)
        XCTAssertEqual(r.recognize(touches: touches(threeBase.map { ($0.0 + 0.20, $0.1) }), timestamp: 0.10), .swipe(.right))
        XCTAssertNil(r.recognize(touches: [], timestamp: 0.30))  // fingers lifted → reset
        // New gesture fires again.
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.40)
        _ = r.recognize(touches: touches(threeBase), timestamp: 0.46)
        XCTAssertEqual(r.recognize(touches: touches(threeBase.map { ($0.0 - 0.20, $0.1) }), timestamp: 0.50), .swipe(.left))
    }
}
