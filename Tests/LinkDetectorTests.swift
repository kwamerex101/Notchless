import XCTest
@testable import Notchless

final class LinkDetectorTests: XCTestCase {
    func test_extractsMultipleLinksInOrder() {
        let links = LinkDetector.links(in: "see https://github.com/foo then https://apple.com/x")
        XCTAssertEqual(links.map(\.domain), ["github.com", "apple.com"])
    }

    func test_dedupesByAbsoluteURL() {
        let links = LinkDetector.links(in: "https://x.com and again https://x.com")
        XCTAssertEqual(links.count, 1)
    }

    func test_stripsLeadingWww() {
        let links = LinkDetector.links(in: "http://www.example.com/page")
        XCTAssertEqual(links.first?.domain, "example.com")
    }

    func test_noLinks_returnsEmpty() {
        XCTAssertTrue(LinkDetector.links(in: "just some plain text").isEmpty)
        XCTAssertTrue(LinkDetector.links(in: "").isEmpty)
    }

    func test_skipsHostlessLinks() {
        // NSDataDetector reads emails as mailto: URLs (no host) — no chip.
        XCTAssertTrue(LinkDetector.links(in: "reach me at a@b.com").isEmpty)
    }
}
