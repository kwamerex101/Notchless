import XCTest
@testable import Notchless

final class SessionGuardTests: XCTestCase {
    func test_beginReturnsFreshGenerationEachTime() {
        var g = SessionGuard()
        let a = g.begin()
        let b = g.begin()
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(b, g.current)
    }

    func test_onlyLatestGenerationIsCurrent() {
        var g = SessionGuard()
        let first = g.begin()
        let second = g.begin()
        XCTAssertFalse(g.isCurrent(first))   // stale session's writes are ignored
        XCTAssertTrue(g.isCurrent(second))
    }
}
