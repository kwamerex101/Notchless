import XCTest
@testable import Notchless

/// Unit tests for the pure `HUDSound` mapping (system sound name +
/// `CaseIterable` completeness). Actual `NSSound` playback is on-device-only
/// and not covered here.
final class HUDSoundTests: XCTestCase {

    func test_systemSoundName_mapsEachCase() {
        XCTAssertEqual(HUDSound.pop.systemSoundName, "Pop")
        XCTAssertEqual(HUDSound.tink.systemSoundName, "Tink")
        XCTAssertEqual(HUDSound.funk.systemSoundName, "Funk")
        XCTAssertEqual(HUDSound.submarine.systemSoundName, "Submarine")
    }

    func test_allCases_hasFourNonEmptyNames() {
        XCTAssertEqual(HUDSound.allCases.count, 4)
        for sound in HUDSound.allCases {
            XCTAssertFalse(sound.systemSoundName.isEmpty)
        }
    }
}
