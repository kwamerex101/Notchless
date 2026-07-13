import XCTest
@testable import Notchless

/// Unit tests for `NowPlayingTransport.ordered`, the pure button-order
/// resolver behind the Now Playing transport row. Actual button rendering
/// and the 15s-skip seek behavior are on-device-only and not covered here.
final class NowPlayingTransportTests: XCTestCase {
    func test_noShuffleNoSkip_isJustCoreThree() {
        XCTAssertEqual(
            NowPlayingTransport.ordered(showShuffle: false, showSkip15: false),
            [.previous, .playPause, .next]
        )
    }

    func test_shuffleOnly_prependsShuffle() {
        XCTAssertEqual(
            NowPlayingTransport.ordered(showShuffle: true, showSkip15: false),
            [.shuffle, .previous, .playPause, .next]
        )
    }

    func test_skip15Only_wrapsCoreThree() {
        XCTAssertEqual(
            NowPlayingTransport.ordered(showShuffle: false, showSkip15: true),
            [.rewind15, .previous, .playPause, .next, .forward15]
        )
    }

    func test_shuffleAndSkip15_bothApplied() {
        XCTAssertEqual(
            NowPlayingTransport.ordered(showShuffle: true, showSkip15: true),
            [.shuffle, .rewind15, .previous, .playPause, .next, .forward15]
        )
    }
}
