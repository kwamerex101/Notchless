import XCTest
@testable import Notchless

private final class MockActuator: HapticActuating {
    var isAvailable = true
    var actuations: [HapticStrength] = []
    func actuate(_ strength: HapticStrength) { actuations.append(strength) }
}

private final class MockPlayer: ClickSounding {
    var preloaded = false
    var plays: [(voice: String, volume: Double)] = []
    func preload() { preloaded = true }
    func play(_ voice: FeedbackVoice, volume: Double) { plays.append((voice.id, volume)) }
}

final class TrackpadFeedbackCoreTests: XCTestCase {
    private var actuator = MockActuator()
    private var player = MockPlayer()

    private func makeCore(hapticsOn: Bool = true, soundOn: Bool = true,
                          scrollOn: Bool = true, clickOn: Bool = true) -> TrackpadFeedbackCore {
        let config = TrackpadFeedbackConfig(
            hapticsOn: hapticsOn, soundOn: soundOn, scrollOn: scrollOn, clickOn: clickOn,
            strength: .medium, voiceID: "twig", volume: 0.72)
        return TrackpadFeedbackCore(config: config, tuning: DetentTuning(),
                                    actuator: actuator, player: player)
    }

    func test_scrollTick_firesHapticAndSoundInSync() {
        let core = makeCore()
        core.handleScroll(delta: 100, timestamp: 0)   // 4 ticks at threshold 24
        XCTAssertEqual(actuator.actuations, [.medium, .medium, .medium, .medium])
        XCTAssertEqual(player.plays.count, 4)
        XCTAssertEqual(player.plays.first?.voice, "twig")
        XCTAssertEqual(player.plays.first?.volume ?? 0, 0.72, accuracy: 0.001)
    }

    func test_clickDownAndUp_eachFireOnce() {
        let core = makeCore()
        core.handleClick(down: true)
        core.handleClick(down: false)
        XCTAssertEqual(actuator.actuations.count, 2)
        XCTAssertEqual(player.plays.count, 2)
    }

    func test_scrollToggleOff_gatesScrollButNotClick() {
        let core = makeCore(scrollOn: false)
        core.handleScroll(delta: 100, timestamp: 0)
        core.handleClick(down: true)
        XCTAssertEqual(actuator.actuations.count, 1)
    }

    func test_clickToggleOff_gatesClickButNotScroll() {
        let core = makeCore(clickOn: false)
        core.handleClick(down: true)
        core.handleScroll(delta: 100, timestamp: 0)
        XCTAssertEqual(actuator.actuations.count, 4)
    }

    func test_hapticsOff_soundStillPlays() {
        let core = makeCore(hapticsOn: false)
        core.handleClick(down: true)
        XCTAssertTrue(actuator.actuations.isEmpty)
        XCTAssertEqual(player.plays.count, 1)
    }

    func test_soundOff_hapticStillFires() {
        let core = makeCore(soundOn: false)
        core.handleClick(down: true)
        XCTAssertEqual(actuator.actuations.count, 1)
        XCTAssertTrue(player.plays.isEmpty)
    }

    func test_actuatorUnavailable_skipsHapticKeepsSound() {
        actuator.isAvailable = false
        let core = makeCore()
        core.handleClick(down: true)
        XCTAssertTrue(actuator.actuations.isEmpty)
        XCTAssertEqual(player.plays.count, 1)
    }

    func test_updateConfig_takesEffect() {
        let core = makeCore()
        core.update(config: TrackpadFeedbackConfig(
            hapticsOn: true, soundOn: true, scrollOn: true, clickOn: true,
            strength: .strong, voiceID: "drop", volume: 0.3))
        core.handleClick(down: true)
        XCTAssertEqual(actuator.actuations, [.strong])
        XCTAssertEqual(player.plays.first?.voice, "drop")
        XCTAssertEqual(player.plays.first?.volume ?? 0, 0.3, accuracy: 0.001)
    }

    func test_fireTest_firesOnePulseIgnoringTypeToggles() {
        let core = makeCore(scrollOn: false, clickOn: false)
        core.fireTest()
        XCTAssertEqual(actuator.actuations.count, 1)
        XCTAssertEqual(player.plays.count, 1)
    }
}

extension TrackpadFeedbackCoreTests {
    func test_handleGesture_firesWhenGesturesOn() {
        let config = TrackpadFeedbackConfig(
            hapticsOn: true, soundOn: true, scrollOn: false, clickOn: false,
            strength: .strong, voiceID: "drop", volume: 0.4, gesturesOn: true)
        let core = TrackpadFeedbackCore(config: config, tuning: DetentTuning(),
                                        actuator: actuator, player: player)
        core.handleGesture()
        XCTAssertEqual(actuator.actuations, [.strong])
        XCTAssertEqual(player.plays.count, 1)
        XCTAssertEqual(player.plays.first?.voice, "drop")
    }

    func test_handleGesture_silentWhenGesturesOff() {
        let config = TrackpadFeedbackConfig(
            hapticsOn: true, soundOn: true, scrollOn: true, clickOn: true,
            strength: .medium, voiceID: "twig", volume: 0.5, gesturesOn: false)
        let core = TrackpadFeedbackCore(config: config, tuning: DetentTuning(),
                                        actuator: actuator, player: player)
        core.handleGesture()
        XCTAssertTrue(actuator.actuations.isEmpty)
        XCTAssertTrue(player.plays.isEmpty)
    }
}
