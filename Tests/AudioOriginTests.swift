import XCTest
@testable import Notchless

/// Unit tests for `AudioService.classifyOrigin`, the pure self-write vs.
/// external classifier. CoreAudio listener wiring, `setVolume`, per-channel
/// listeners, the leak fix, and the capability signal are on-device-only and
/// not covered here.
final class AudioOriginTests: XCTestCase {
    private let window: TimeInterval = 0.15
    private let tolerance: Double = 0.02

    func test_pendingWithinWindowAndTolerance_isSelfWrite() {
        let now = Date()
        let pending = (target: 0.5, at: now.addingTimeInterval(-0.1))
        let origin = AudioService.classifyOrigin(
            level: 0.5, now: now, pending: pending, window: window, tolerance: tolerance
        )
        XCTAssertEqual(origin, .selfWrite)
    }

    func test_pendingBeyondWindow_isExternal() {
        let now = Date()
        let pending = (target: 0.5, at: now.addingTimeInterval(-0.2))
        let origin = AudioService.classifyOrigin(
            level: 0.5, now: now, pending: pending, window: window, tolerance: tolerance
        )
        XCTAssertEqual(origin, .external)
    }

    func test_pendingWithinWindowButBeyondTolerance_isExternal() {
        let now = Date()
        let pending = (target: 0.5, at: now.addingTimeInterval(-0.1))
        let origin = AudioService.classifyOrigin(
            level: 0.6, now: now, pending: pending, window: window, tolerance: tolerance
        )
        XCTAssertEqual(origin, .external)
    }

    func test_noPending_isExternal() {
        let now = Date()
        let origin = AudioService.classifyOrigin(
            level: 0.5, now: now, pending: nil, window: window, tolerance: tolerance
        )
        XCTAssertEqual(origin, .external)
    }

    /// Boundary: exactly at `window` and exactly at `tolerance` are inclusive
    /// per the `<=` rules in the spec, so this should still classify as
    /// `.selfWrite`. Uses binary-exact values — `window = 0.5`,
    /// `tolerance = 0.25` (both exact powers of two), and a near-zero
    /// reference date rather than `Date()` — so the boundary arithmetic
    /// lands exactly on the limit instead of drifting a Double ULP past it
    /// (which is what `Date()` at epoch-scale magnitude, or decimals like
    /// 0.15/0.02, would do) and flipping the comparison the test means to
    /// exercise.
    func test_exactlyAtWindowAndToleranceBoundary_isSelfWrite() {
        let exactWindow: TimeInterval = 0.5
        let exactTolerance = 0.25
        let at = Date(timeIntervalSinceReferenceDate: 0)
        let now = at.addingTimeInterval(exactWindow)
        let pending = (target: 0.5, at: at)
        let origin = AudioService.classifyOrigin(
            level: pending.target + exactTolerance, now: now, pending: pending,
            window: exactWindow, tolerance: exactTolerance
        )
        XCTAssertEqual(origin, .selfWrite)
    }
}
