import XCTest
@testable import Notchless

final class NowPlayingFilterTests: XCTestCase {
    func test_shouldAccept_systemWideAlwaysTrue() {
        XCTAssertTrue(NowPlayingFilter.shouldAccept(bundleID: "x", source: .systemWide, allowed: []))
    }

    func test_shouldAccept_specificAppsAllowedTrue() {
        XCTAssertTrue(NowPlayingFilter.shouldAccept(bundleID: "x", source: .specificApps, allowed: ["x"]))
    }

    func test_shouldAccept_specificAppsNotAllowedFalse() {
        XCTAssertFalse(NowPlayingFilter.shouldAccept(bundleID: "x", source: .specificApps, allowed: ["y"]))
    }

    func test_shouldAccept_specificAppsNilBundleFalse() {
        XCTAssertFalse(NowPlayingFilter.shouldAccept(bundleID: nil, source: .specificApps, allowed: []))
    }

    func test_addSeen_prependsToEmptyList() {
        XCTAssertEqual(NowPlayingFilter.addSeen("a", to: []), ["a"])
    }

    func test_addSeen_dedupesExistingEntry() {
        let result = NowPlayingFilter.addSeen("a", to: ["a", "b"])
        XCTAssertTrue(result.contains("a"))
        XCTAssertEqual(result.count, 2)
    }

    func test_addSeen_trimsToCapWhenFull() {
        let full = (0..<20).map { "app\($0)" }
        let result = NowPlayingFilter.addSeen("newApp", to: full, cap: 20)
        XCTAssertEqual(result.count, 20)
        XCTAssertEqual(result.first, "newApp")
        XCTAssertFalse(result.contains("app19"))
    }
}
