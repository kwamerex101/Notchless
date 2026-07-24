import XCTest
import Combine
@testable import Notchless

/// Reproduces the real `NotchMouseTracker.start()` wiring — a sink on
/// `model.objectWillChange` that calls `controller.evaluate()` synchronously
/// — and drives the controller into a state transition that flips
/// `revealActive`. Without the `isApplying` re-entrancy latch in
/// `FullscreenRevealController.apply(_:)`, writing `model.revealActive`
/// fires `objectWillChange` in `willSet` (before the new value commits),
/// the sink calls back into `evaluate()` → `apply()`, the value-comparison
/// dedup there still sees the old value and writes again, and the cycle
/// recurses without bound (stack overflow on the first real reveal
/// transition in fullscreen).
@MainActor
final class FullscreenRevealControllerTests: XCTestCase {
    func test_revealActiveWriteDoesNotRecurseThroughObjectWillChangeSink() {
        // Isolated, in-memory settings so this never touches the user's real
        // UserDefaults / iCloud key-value store (see StoredTests.FakeKVS).
        let suiteName = "FullscreenRevealControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults, kvs: FakeKVS())
        settings.hideInFullscreen = true

        let model = NotchViewModel(settings: settings)
        let controller = FullscreenRevealController(panel: nil, settings: settings, model: model)

        var sinkInvocations = 0
        // Exactly what NotchMouseTracker.start()'s contentObserver does.
        let cancellable = model.objectWillChange.sink { _ in
            sinkInvocations += 1
            controller.evaluate()
        }
        defer { cancellable.cancel() }

        // Content that holds reveal open regardless of cursor position, so
        // the machine transitions straight to `.revealed` once fullscreen
        // engages — no mouse plumbing needed to trigger the bug.
        model.hud = .sound(level: 0.5, muted: false)
        model.fullscreenActive = true

        // The real transition under test: this write flips
        // machine.state to .revealed and, without the latch, recurses.
        controller.evaluate()

        XCTAssertTrue(model.revealActive, "reveal should have engaged for held-open content in fullscreen")
        XCTAssertTrue(model.fullscreenActive)

        // Bounded, not "didn't crash": each @Published write on the way to
        // .revealed (hud, fullscreenActive, revealActive) fires the sink
        // once for its own change; the latch drops every nested evaluate()
        // triggered mid-write before it can write again. Without the latch
        // this count is unbounded (the process crashes/hangs before it is
        // ever read).
        XCTAssertLessThanOrEqual(sinkInvocations, 6, "objectWillChange sink should not be re-entered without bound")
    }

    /// Reproduces the real `NotchMouseTracker` wiring end-to-end (Bug 1):
    /// `objectWillChange` fires from `@Published`'s `willSet`, before the new
    /// value commits, so a synchronous `evaluate()` inside the sink reads the
    /// OLD content. A volume HUD written in fullscreen would then be judged
    /// against pre-HUD content, stay `.hidden`, and render at alpha 0 for its
    /// whole life. `NotchMouseTracker.start()`'s content observer must defer
    /// `evaluate()` to the next runloop turn so it reads the committed value.
    func test_trackerContentObserver_deferredEvaluate_seesCommittedHUD() {
        let suiteName = "FullscreenRevealControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults, kvs: FakeKVS())
        settings.hideInFullscreen = true

        let model = NotchViewModel(settings: settings)
        let controller = FullscreenRevealController(panel: nil, settings: settings, model: model)
        let panel = NotchPanel(contentRect: .zero)
        let metrics = NotchMetrics(
            notchWidth: 200, notchHeight: 32, notchCenterX: 500, screenTopY: 800, hasRealNotch: false
        )
        let tracker = NotchMouseTracker(panel: panel, model: model, metrics: metrics)
        tracker.reveal = controller
        tracker.start()
        defer { tracker.stop() }

        model.fullscreenActive = true

        func waitOneRunloopTurn() {
            let settled = expectation(description: "runloop turn")
            DispatchQueue.main.async { settled.fulfill() }
            wait(for: [settled], timeout: 1.0)
        }

        waitOneRunloopTurn()
        XCTAssertFalse(model.revealActive, "nothing engaging yet — must not be revealed")

        model.hud = .sound(level: 0.5, muted: false)

        // Right after the write, on this same runloop turn, the deferred hop
        // has not run yet — this is what distinguishes the fix from a
        // synchronous call, which would (wrongly) evaluate here against the
        // still-nil `model.hud`.
        XCTAssertFalse(model.revealActive, "must not reveal synchronously off pre-commit content")

        waitOneRunloopTurn()
        XCTAssertTrue(model.revealActive, "HUD should engage reveal once the deferred evaluate reads committed content")
    }

    /// Reproduces `EffectsController`'s real `settings.$hideInFullscreen`
    /// wiring (Bug 3): the sink fires before `settings.hideInFullscreen`
    /// commits (same `willSet` timing as `objectWillChange`), so re-reading
    /// the property inside the sink sees the OLD (`false`) value. The fix
    /// passes the sink's `on` value straight through via
    /// `evaluate(hidingEnabledOverride:)` instead.
    func test_hideInFullscreenSink_engagesOffCommittedOnValue_notStaleProperty() {
        let suiteName = "FullscreenRevealControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults, kvs: FakeKVS())
        settings.hideInFullscreen = false

        let model = NotchViewModel(settings: settings)
        model.fullscreenActive = true

        // No panel: `lastNotchRect`/`screenFrame` default to `.zero`, so the
        // real on-screen cursor can never land inside the (zero-area) band or
        // notch rect — the same trick the recursion test above relies on to
        // stay independent of actual cursor position.
        let controller = FullscreenRevealController(panel: nil, settings: settings, model: model)
        controller.evaluate()
        XCTAssertTrue(controller.allowsInteraction, "hiding is off — panel must start interactive")

        // Mirrors EffectsController's real sink: pass `on` straight through
        // rather than let `evaluate()` re-read `settings.hideInFullscreen`.
        let cancellable = settings.$hideInFullscreen
            .dropFirst()  // ignore the immediate replay of the current value on subscribe
            .sink { on in
                if on { controller.evaluate(hidingEnabledOverride: on) }
            }
        defer { cancellable.cancel() }

        settings.hideInFullscreen = true

        // Cursor disengaged, no held-open content: turning hiding on while
        // already fullscreen must hide immediately off this single write —
        // no mouse move, no 1s settle recheck needed.
        XCTAssertFalse(
            controller.allowsInteraction,
            "hiding should engage off the sink's committed `on` value, not the stale settings property"
        )
    }
}
