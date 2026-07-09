import Foundation

/// One decoded multitouch contact (from a raw MTTouch). Positions are
/// normalized trackpad coordinates in [0,1].
struct FingerTouch: Equatable {
    let x: Double
    let y: Double
    let id: Int
    let state: Int

    /// MTTouchState value for a finger actively on the surface. Frames also
    /// carry leaving/lingering touches, which must not be counted.
    static let touching = 4
}

enum GestureDirection { case left, right, up, down }

/// A recognized discrete gesture (v1: no continuous/detent gestures).
enum GestureTick: Equatable {
    case swipe(GestureDirection)
    case pinch
    case spread
}

/// Recognition thresholds, in normalized [0,1] trackpad units (NOT the scroll
/// DetentTuning pixel constants). Immutable after the monitor starts. Defaults
/// chosen blind; confirmed by the on-device pass (Task 7).
struct GestureTuning {
    /// Centroid travel (normalized) to commit a swipe.
    var swipeThreshold: Double = 0.15
    /// Mean finger-distance-from-centroid change (normalized) to commit pinch/spread.
    var pinchThreshold: Double = 0.12
    /// |primary axis| must exceed this × |other axis| to pick a swipe direction.
    var dominanceRatio: Double = 1.5
    /// Seconds the (peak) finger count must hold before the gesture arms — absorbs
    /// asynchronous finger land/lift.
    var settleWindow: TimeInterval = 0.05
    /// Minimum touching fingers for a gesture (3; pinch/spread additionally need 4).
    var gestureMinFingers: Int = 3
}
