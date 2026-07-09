import XCTest
@testable import Notchless

final class ClickSoundPlayerTests: XCTestCase {
    func test_preload_decodesEveryBundledVoice() {
        let player = ClickSoundPlayer()
        player.preload()
        XCTAssertEqual(Set(player.loadedVoiceIDs), Set(FeedbackVoice.all.map(\.id)))
    }

    func test_play_neverCrashes_evenHeadless() {
        let player = ClickSoundPlayer()
        player.preload()
        player.play(FeedbackVoice.all[0], volume: 0.5)   // engine may fail to start on CI — must not crash
        let done = expectation(description: "queue drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    func test_playWithoutPreload_noCrash() {
        let player = ClickSoundPlayer()
        player.play(FeedbackVoice.all[1], volume: 0.5)   // no buffer yet → silent no-op
    }
}
