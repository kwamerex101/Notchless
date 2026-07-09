import Foundation
import os

/// The synchronous heart of trackpad feedback: turns scroll/click events into
/// actuator + sound calls per the current config. Thread-safe — the event tap
/// calls in from its own thread while the controller updates config from main.
/// Deliberately does NOT know about CGEvents, settings, or permissions.
final class TrackpadFeedbackCore {
    private let actuator: HapticActuating
    private let player: ClickSounding

    private struct State {
        var config: TrackpadFeedbackConfig
        var accumulator: ScrollDetentAccumulator
    }
    private let state: OSAllocatedUnfairLock<State>

    init(config: TrackpadFeedbackConfig, tuning: DetentTuning,
         actuator: HapticActuating, player: ClickSounding) {
        self.actuator = actuator
        self.player = player
        self.state = OSAllocatedUnfairLock(initialState:
            State(config: config, accumulator: ScrollDetentAccumulator(tuning: tuning)))
    }

    func update(config: TrackpadFeedbackConfig) {
        state.withLock { $0.config = config }
    }

    func handleScroll(delta: Double, timestamp: TimeInterval) {
        let (config, ticks): (TrackpadFeedbackConfig, Int) = state.withLock { s in
            guard s.config.scrollOn else { return (s.config, 0) }
            return (s.config, s.accumulator.ticks(delta: delta, timestamp: timestamp))
        }
        for _ in 0..<ticks { fire(config) }
    }

    func handleClick(down: Bool) {
        let config = state.withLock { $0.config }
        guard config.clickOn else { return }
        fire(config)   // one pulse each for down and up
    }

    /// One unconditional pulse for the Settings "Test" button (ignores the
    /// scroll/click type toggles, honors haptics/sound/strength/voice/volume).
    func fireTest() {
        fire(state.withLock { $0.config })
    }

    private func fire(_ config: TrackpadFeedbackConfig) {
        if config.hapticsOn, actuator.isAvailable {
            actuator.actuate(config.strength)
        }
        if config.soundOn {
            player.play(FeedbackVoice.voice(id: config.voiceID), volume: config.volume)
        }
    }
}
