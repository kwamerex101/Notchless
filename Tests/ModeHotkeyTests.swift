import XCTest
@testable import Notchless

final class ModeHotkeyTests: XCTestCase {
    func test_hotkeyRoundTripsInCodable() throws {
        var m = Mode(name: "Email", systemImage: "envelope")
        m.hotkey = .controlCommand
        let back = try JSONDecoder().decode(Mode.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(back.hotkey, .controlCommand)
    }

    func test_availableExcludesMainAndOtherEnabledModes() {
        var a = Mode(name: "A", systemImage: "a"); a.hotkey = .controlCommand; a.isEnabled = true
        var b = Mode(name: "B", systemImage: "b"); b.isEnabled = true
        let avail = availableHotkeys(for: b, main: .controlOption, modes: [a, b])
        XCTAssertFalse(avail.contains(.controlOption))   // main excluded
        XCTAssertFalse(avail.contains(.controlCommand))  // taken by enabled A
        XCTAssertTrue(avail.contains(.fnCommand))         // free
    }

    func test_availableIncludesOwnCurrentHotkey() {
        var a = Mode(name: "A", systemImage: "a"); a.hotkey = .controlCommand; a.isEnabled = true
        let avail = availableHotkeys(for: a, main: .controlOption, modes: [a])
        XCTAssertTrue(avail.contains(.controlCommand))   // its own key stays selectable
    }

    func test_disabledModeDoesNotReserveItsCombo() {
        var a = Mode(name: "A", systemImage: "a"); a.hotkey = .controlCommand; a.isEnabled = false
        var b = Mode(name: "B", systemImage: "b"); b.isEnabled = true
        let avail = availableHotkeys(for: b, main: .controlOption, modes: [a, b])
        XCTAssertTrue(avail.contains(.controlCommand))   // disabled A doesn't reserve it
    }
}
