import XCTest
import CoreGraphics
@testable import Notchless

final class HotkeyMatcherTests: XCTestCase {
    private let mainID: UUID? = nil
    private let modeID = UUID()

    private func bindings() -> [HotkeyBinding] {
        [HotkeyBinding(id: mainID, flags: [.maskControl, .maskAlternate]),   // main = ⌃⌥
         HotkeyBinding(id: modeID, flags: [.maskControl, .maskCommand])]     // mode = ⌃⌘
    }

    func test_exactMatchMain() {
        let m = HotkeyMatcher.match(held: [.maskControl, .maskAlternate], bindings: bindings())
        XCTAssertEqual(m?.id, mainID); XCTAssertNotNil(m)
    }

    func test_exactMatchMode() {
        let m = HotkeyMatcher.match(held: [.maskControl, .maskCommand], bindings: bindings())
        XCTAssertEqual(m?.id, modeID)
    }

    func test_supersetDoesNotMatchSmallerCombo() {
        // ⌃⌥⌘ held — neither ⌃⌥ nor ⌃⌘ exactly matches.
        let m = HotkeyMatcher.match(held: [.maskControl, .maskAlternate, .maskCommand], bindings: bindings())
        XCTAssertNil(m)
    }

    func test_ignoresNonComboBits() {
        // ⌃⌥ + caps lock still matches ⌃⌥.
        let m = HotkeyMatcher.match(held: [.maskControl, .maskAlternate, .maskAlphaShift], bindings: bindings())
        XCTAssertEqual(m?.id, mainID)
    }

    func test_noMatchReturnsNil() {
        XCTAssertNil(HotkeyMatcher.match(held: [.maskShift], bindings: bindings()))
        XCTAssertNil(HotkeyMatcher.match(held: [], bindings: bindings()))
    }

    func test_firstBindingWinsOnDuplicateCombo() {
        let dupe = [HotkeyBinding(id: nil, flags: [.maskControl]),
                    HotkeyBinding(id: modeID, flags: [.maskControl])]
        XCTAssertNil(HotkeyMatcher.match(held: [.maskControl], bindings: dupe)?.id)  // main (nil) wins
    }
}
