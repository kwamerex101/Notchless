import Foundation

/// Pure, deterministic multi-finger gesture recognizer. Fed one contact frame
/// at a time (timestamps passed in, no clocks), it emits at most one discrete
/// `GestureTick` per gesture. Mirrors `ScrollDetentAccumulator`'s value-type,
/// testable shape. Mutated only on the MT callback thread — no lock.
struct MultitouchGestureRecognizer {
    let tuning: GestureTuning

    private var peakCount = 0
    private var countStableSince: TimeInterval = 0
    private var armed = false
    private var latched = false
    private var startCX = 0.0, startCY = 0.0, startRadius = 0.0

    init(tuning: GestureTuning) { self.tuning = tuning }

    mutating func reset() {
        peakCount = 0
        countStableSince = 0
        armed = false
        latched = false
    }

    mutating func recognize(touches: [FingerTouch], timestamp: TimeInterval) -> GestureTick? {
        let active = touches.filter { $0.state == FingerTouch.touching }
        let n = active.count
        guard n >= tuning.gestureMinFingers else { reset(); return nil }

        let cx = active.reduce(0.0) { $0 + $1.x } / Double(n)
        let cy = active.reduce(0.0) { $0 + $1.y } / Double(n)
        let radius = active.reduce(0.0) { $0 + hypot($1.x - cx, $1.y - cy) } / Double(n)

        // Peak-count increase restarts the settle window (absorbs finger land order).
        if n > peakCount {
            peakCount = n
            countStableSince = timestamp
            armed = false
        }
        // Arm once the peak count has been stable long enough; capture the baseline.
        if !armed, timestamp - countStableSince >= tuning.settleWindow {
            armed = true
            startCX = cx
            startCY = cy
            startRadius = radius
        }
        guard armed, !latched else { return nil }

        let dx = cx - startCX
        let dy = cy - startCY
        let dr = radius - startRadius
        let dist = hypot(dx, dy)

        // Pinch/spread is 4-finger; when both cross, take the stronger normalized signal.
        let swipeScore = dist / tuning.swipeThreshold
        if peakCount >= 4, abs(dr) >= tuning.pinchThreshold,
           abs(dr) / tuning.pinchThreshold >= swipeScore {
            latched = true
            return dr < 0 ? .pinch : .spread
        }

        if dist >= tuning.swipeThreshold {
            if abs(dx) >= tuning.dominanceRatio * abs(dy) {
                latched = true
                return dx > 0 ? .swipe(.right) : .swipe(.left)
            }
            if abs(dy) >= tuning.dominanceRatio * abs(dx) {
                latched = true
                // Normalized y increases toward the top of the pad → .up.
                // (Orientation confirmed/flipped by the on-device pass.)
                return dy > 0 ? .swipe(.up) : .swipe(.down)
            }
            // Diagonal: wait for one axis to dominate.
        }
        return nil
    }
}
