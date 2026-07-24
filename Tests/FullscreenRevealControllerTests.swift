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
}
