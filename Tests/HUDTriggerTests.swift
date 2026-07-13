import XCTest
@testable import Notchless

/// Unit tests for the two pure HUD-trigger helpers:
/// `NotchViewModel.clampHUDDelay` (hide-delay clamping) and
/// `HUDController.shouldShowVolumeHUD` (external-volume gating + AX
/// fallback). Real key-vs-external correlation timing and the AX trust
/// state itself are on-device-only and not covered here.
final class HUDTriggerTests: XCTestCase {

    // MARK: - clampHUDDelay

    func test_clampHUDDelay_belowRange_clampsToMin() {
        XCTAssertEqual(NotchViewModel.clampHUDDelay(0.1), 0.5)
    }

    func test_clampHUDDelay_aboveRange_clampsToMax() {
        XCTAssertEqual(NotchViewModel.clampHUDDelay(9.0), 5.0)
    }

    func test_clampHUDDelay_inRange_unchanged() {
        XCTAssertEqual(NotchViewModel.clampHUDDelay(2.0), 2.0)
    }

    func test_clampHUDDelay_boundaries_unchanged() {
        XCTAssertEqual(NotchViewModel.clampHUDDelay(0.5), 0.5)
        XCTAssertEqual(NotchViewModel.clampHUDDelay(5.0), 5.0)
    }

    // MARK: - shouldShowVolumeHUD

    func test_initial_alwaysFalse() {
        let now = Date()
        XCTAssertFalse(HUDController.shouldShowVolumeHUD(
            origin: .initial, showOnExternal: true, axTrusted: true,
            lastVolumeKeyAt: now, now: now
        ))
        XCTAssertFalse(HUDController.shouldShowVolumeHUD(
            origin: .initial, showOnExternal: false, axTrusted: false,
            lastVolumeKeyAt: nil, now: now
        ))
    }

    func test_selfWrite_alwaysTrue() {
        let now = Date()
        XCTAssertTrue(HUDController.shouldShowVolumeHUD(
            origin: .selfWrite, showOnExternal: false, axTrusted: true,
            lastVolumeKeyAt: nil, now: now
        ))
        XCTAssertTrue(HUDController.shouldShowVolumeHUD(
            origin: .selfWrite, showOnExternal: true, axTrusted: false,
            lastVolumeKeyAt: now, now: now
        ))
    }

    func test_external_showOnExternalTrue_isTrue() {
        let now = Date()
        XCTAssertTrue(HUDController.shouldShowVolumeHUD(
            origin: .external, showOnExternal: true, axTrusted: true,
            lastVolumeKeyAt: nil, now: now
        ))
    }

    func test_external_showOnExternalFalse_axNotTrusted_fallsBackToTrue() {
        let now = Date()
        XCTAssertTrue(HUDController.shouldShowVolumeHUD(
            origin: .external, showOnExternal: false, axTrusted: false,
            lastVolumeKeyAt: nil, now: now
        ))
    }

    func test_external_showOnExternalFalse_axTrusted_recentKey_isTrue() {
        let now = Date()
        let recentKey = now.addingTimeInterval(-0.1)
        XCTAssertTrue(HUDController.shouldShowVolumeHUD(
            origin: .external, showOnExternal: false, axTrusted: true,
            lastVolumeKeyAt: recentKey, now: now, keyWindow: 0.3
        ))
    }

    func test_external_showOnExternalFalse_axTrusted_noOrOldKey_isFalse() {
        let now = Date()
        let oldKey = now.addingTimeInterval(-1.0)
        XCTAssertFalse(HUDController.shouldShowVolumeHUD(
            origin: .external, showOnExternal: false, axTrusted: true,
            lastVolumeKeyAt: oldKey, now: now, keyWindow: 0.3
        ))
        XCTAssertFalse(HUDController.shouldShowVolumeHUD(
            origin: .external, showOnExternal: false, axTrusted: true,
            lastVolumeKeyAt: nil, now: now, keyWindow: 0.3
        ))
    }
}
