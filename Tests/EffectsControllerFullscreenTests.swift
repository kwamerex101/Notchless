import XCTest
@testable import Notchless

/// Coverage for the fullscreen-detection heuristic behind
/// `EffectsController.isFullscreenSpaceActive` — its pure `coversNotchTopBand`
/// core, exercised against synthetic on-screen window lists (issue #25). The
/// live method still reads `CGWindowListCopyWindowInfo`/`NSScreen`; only the
/// decision is unit-tested here.
final class EffectsControllerFullscreenTests: XCTestCase {
    /// A 1440×900 built-in display at the AppKit origin. For the built-in
    /// (notch screen == primary) the CG top band sits at y 0…3.
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func covers(_ windows: [(layer: Int, bounds: CGRect)],
                        notch: CGRect? = nil) -> Bool {
        EffectsController.coversNotchTopBand(
            notchScreenFrame: notch ?? primary,
            primaryScreenFrame: primary,
            windows: windows)
    }

    func test_fullscreenWindow_coversTopBand_true() {
        XCTAssertTrue(covers([(layer: 0, bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))]))
    }

    func test_smallWindowAtTop_false() {
        // Reaches the top edge but only 200pt wide — a parked window, not fullscreen.
        XCTAssertFalse(covers([(layer: 0, bounds: CGRect(x: 0, y: 0, width: 200, height: 60))]))
    }

    func test_wideWindowBelowTop_false() {
        // Full width but starts below the 3pt top band.
        XCTAssertFalse(covers([(layer: 0, bounds: CGRect(x: 0, y: 30, width: 1440, height: 700))]))
    }

    func test_nonNormalLayer_ignored_false() {
        // A full-width window at the top on a non-zero layer (e.g. the menu bar)
        // is not counted.
        XCTAssertFalse(covers([(layer: 25, bounds: CGRect(x: 0, y: 0, width: 1440, height: 24))]))
    }

    func test_multiWindow_oneFullscreen_true() {
        XCTAssertTrue(covers([
            (layer: 0, bounds: CGRect(x: 40, y: 200, width: 300, height: 200)),
            (layer: 0, bounds: CGRect(x: 0, y: 0, width: 1440, height: 878)),
        ]))
    }

    func test_noWindows_false() {
        XCTAssertFalse(covers([]))
    }

    func test_widthThreshold_exactly80Percent_true() {
        // 1152 == 0.8 × 1440 — the ≥ boundary counts.
        XCTAssertTrue(covers([(layer: 0, bounds: CGRect(x: 0, y: 0, width: 1152, height: 3))]))
    }

    func test_widthThreshold_justUnder_false() {
        XCTAssertFalse(covers([(layer: 0, bounds: CGRect(x: 0, y: 0, width: 1151, height: 3))]))
    }

    /// On an external display the top band is offset by the AppKit→CG flip
    /// (primary.maxY − screen.maxY). A window covering the external screen's top
    /// must count there, while one at the PRIMARY top must not.
    func test_externalDisplay_topBandFollowsScreen() {
        // External 1920×1080 to the right, its top 380pt above primary's.
        let external = CGRect(x: 1440, y: 200, width: 1920, height: 1080)
        // CG top band for external = y 900 − 1280 = −380 … −377.
        let onExternalTop = (layer: 0, bounds: CGRect(x: 1440, y: -380, width: 1920, height: 1080))
        let onPrimaryTop = (layer: 0, bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertTrue(covers([onExternalTop], notch: external))
        XCTAssertFalse(covers([onPrimaryTop], notch: external))
    }
}
