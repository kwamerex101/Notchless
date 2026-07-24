import AppKit

/// Owns one `FullscreenRevealMachine` and is the single authority for panel
/// alpha and interactivity while a fullscreen app owns the notch's screen.
/// Callers — the mouse tracker on every move, `EffectsController` on
/// fullscreen transitions, `NotchMouseTracker`'s content observer on HUD/
/// notification changes — all funnel through `evaluate()`; this class owns
/// turning the machine's output into the actual panel write and grace-timer
/// scheduling, so nothing else touches `panel.alphaValue` in fullscreen.
@MainActor
final class FullscreenRevealController {
    weak var panel: NotchPanel?
    private let settings: SettingsStore
    private let model: NotchViewModel

    private var machine = FullscreenRevealMachine()
    /// The notch's interactive rect, refreshed by the mouse tracker (the only
    /// caller that has a fresh one on every move). Other callers — the grace
    /// timer, content-driven re-evaluation — re-evaluate against whatever was
    /// last supplied, which is fine: the rect only changes shape, not on the
    /// cadence those callers fire at.
    private var lastNotchRect: CGRect = .zero
    private var graceWork: DispatchWorkItem?
    private var lastAlpha: CGFloat = 1

    /// Guards against re-entry into `apply(_:)`: writing `model.revealActive`
    /// fires `objectWillChange` in `willSet`, which `NotchMouseTracker`'s
    /// content observer turns straight back into an `evaluate()` call — and
    /// at that point `model.revealActive` has not committed yet, so the
    /// value-comparison dedup a few lines down would not stop it, sending
    /// `apply` right back into the same write and recursing without bound.
    /// The latch lives on `apply` itself, not on `evaluate()`/`reset()`,
    /// because `apply` is the sole place that performs the reentrant-causing
    /// write and it's the only thing that must not resume mid-flight; the
    /// nested `evaluate()` call above it is harmless to let run; it
    /// re-derives the same `FullscreenRevealMachine.Output` from unchanged
    /// input (the machine's transition is deterministic), so it doesn't
    /// corrupt state. It only becomes a problem once that recomputed output
    /// reaches `apply` and tries to write again — which is exactly where
    /// this guard sits. The outer `apply` call is still on the stack and
    /// will finish committing the value, so the nested one is simply
    /// dropped.
    private var isApplying = false

    /// The last output's interactivity. `NotchMouseTracker` consults this
    /// before flipping `ignoresMouseEvents`. Defaults true so nothing is
    /// blocked before the first `evaluate()` runs.
    private(set) var allowsInteraction: Bool = true

    init(panel: NotchPanel?, settings: SettingsStore, model: NotchViewModel) {
        self.panel = panel
        self.settings = settings
        self.model = model
    }

    /// - Parameter hidingEnabledOverride: When non-nil, used instead of
    ///   reading `settings.hideInFullscreen`. `EffectsController`'s
    ///   `$hideInFullscreen` sink fires from `willSet`, before the setting's
    ///   new value commits — reading the property at that instant would see
    ///   the OLD value, so the sink passes its `on` value through here
    ///   rather than let `input(hidingEnabled:)` re-read the stale property.
    func evaluate(notchRect: CGRect? = nil, hidingEnabledOverride: Bool? = nil) {
        if let notchRect { lastNotchRect = notchRect }
        apply(machine.update(input(hidingEnabled: hidingEnabledOverride ?? settings.hideInFullscreen), now: Date()))
    }

    /// Drops the machine back to idle and restores full visibility. Called
    /// when `hideInFullscreen` is switched off at runtime (so the panel
    /// doesn't stay stuck mid-fade) and when the panel moves to a different
    /// screen (so a stale `.hidden` from the old screen doesn't leave the new
    /// one invisible before the next real evaluate()).
    func reset() {
        machine = FullscreenRevealMachine()
        graceWork?.cancel()
        graceWork = nil
        apply(machine.update(input(hidingEnabled: false), now: Date()))
    }

    private func input(hidingEnabled: Bool) -> FullscreenRevealMachine.Input {
        FullscreenRevealMachine.Input(
            hidingEnabled: hidingEnabled,
            fullscreenActive: model.fullscreenActive,
            cursor: NSEvent.mouseLocation,
            screenFrame: panel?.screen?.frame ?? .zero,
            notchRect: lastNotchRect,
            content: model.content,
            interaction: model.interaction
        )
    }

    private func apply(_ output: FullscreenRevealMachine.Output) {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        allowsInteraction = output.allowsInteraction

        // Skip the write when unchanged so this doesn't churn on every mouse
        // move — evaluate() runs on every global mouse event.
        if output.alpha != lastAlpha {
            lastAlpha = output.alpha
            NSAnimationContext.runAnimationGroup { context in
                context.duration = FullscreenRevealMachine.fadeDuration
                panel?.animator().alphaValue = output.alpha
            }
        }

        // Only write on real change — same-value @Published writes still
        // invalidate the whole notch view tree (see
        // EffectsController.applyFullscreenState()).
        let revealed = machine.state == .revealed
        if model.revealActive != revealed {
            model.revealActive = revealed
        }

        if let deadline = output.graceDeadline {
            graceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.evaluate() }
            graceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: work)
        } else {
            graceWork?.cancel()
            graceWork = nil
        }
    }
}
