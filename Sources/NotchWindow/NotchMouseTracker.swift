import AppKit
import Combine

/// Makes the notch panel genuinely click-through everywhere except over the
/// notch itself. Returning nil from `hitTest` does NOT pass clicks to the app
/// below — the panel swallows them — so instead we toggle
/// `panel.ignoresMouseEvents` based on the cursor position. Global + local
/// mouse monitors (mouse events need no special permission) tell us when the
/// cursor enters/leaves the current notch shape, and we also drive the notch's
/// hover state from the same signal.
///
/// This is also the sampling point for fullscreen edge-reveal: every mouse
/// move and every content change hands the current notch rect to
/// `FullscreenRevealController`, which decides visibility and whether the
/// panel may become interactive.
@MainActor
final class NotchMouseTracker {
    private weak var panel: NotchPanel?
    private let model: NotchViewModel
    var metrics: NotchMetrics { didSet { rectDirty = true } }
    /// Set by AppDelegate after construction. Weak: the controller owns no
    /// reference back to the tracker.
    weak var reveal: FullscreenRevealController?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isOverNotch = false
    /// Separate dedup from `isOverNotch` — reveal state can change
    /// (band hover, HUD, grace expiry) while the cursor never crosses the
    /// notch rect, so interactivity needs its own change-gate.
    private var wasInteractive = false

    /// Cached interactive rect + a dirty flag, so we don't recompute `NotchSizing`
    /// (a big switch) on every system-wide mouse move — only after the notch's
    /// content actually changes shape.
    private var cachedRect: CGRect = .zero
    private var rectDirty = true
    private var contentObserver: AnyCancellable?
    /// Coalesces the content observer's deferred `evaluate()` calls — see
    /// `start()` — so a burst of `@Published` writes in one runloop turn
    /// (e.g. every field a HUD write touches) schedules a single deferred
    /// evaluate rather than one per publish.
    private var deferredEvaluateScheduled = false

    init(panel: NotchPanel, model: NotchViewModel, metrics: NotchMetrics) {
        self.panel = panel
        self.model = model
        self.metrics = metrics
    }

    func start() {
        panel?.ignoresMouseEvents = true  // pass-through by default

        // Any model change may resize the notch; mark the rect stale so the next
        // evaluate() recomputes it once. Cheap bool flip vs. per-move sizing.
        // Also re-evaluate reveal directly: a HUD or notification can appear
        // with no mouse movement at all (e.g. a volume key press), and reveal
        // must react to that content change on its own, not wait for the next
        // move. Safe against recursion — see evaluate()'s own dedup below.
        contentObserver = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.rectDirty = true
            // `objectWillChange` fires from `@Published`'s `willSet`, which
            // runs BEFORE the new value commits — a reader inside this sink
            // (directly, or via `evaluate()` -> `FullscreenRevealController`
            // -> `model.content`) still sees the OLD value. Calling
            // `evaluate()` synchronously here made HUDs render invisible
            // (reveal read pre-HUD content) and cleared `rectDirty` against
            // a stale rect. Defer one runloop turn so `evaluate()` runs
            // after the value has committed. Do NOT "simplify" this back to
            // a synchronous call — that reintroduces the pre-commit read.
            guard !self.deferredEvaluateScheduled else { return }
            self.deferredEvaluateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.deferredEvaluateScheduled = false
                self.evaluate()
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            self?.evaluate()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.evaluate()
            return event
        }
        evaluate()
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        contentObserver = nil
    }

    /// The current interactive rect, recomputed only when marked dirty by a
    /// model change (or when `metrics` changed). Screen-space, bottom-left
    /// origin to match `NSEvent.mouseLocation`, with slack for easy targeting.
    private func currentRect() -> CGRect {
        if rectDirty {
            cachedRect = NotchSizing.screenBand(for: model.content, metrics: metrics, pad: 6, dictationSettled: model.dictationSettled)
            rectDirty = false
        }
        return cachedRect
    }

    private func evaluate() {
        let rect = currentRect()

        // Reveal must run before the `over` dedup below: the reveal band
        // spans the full screen width while the notch rect is only a few
        // hundred points wide, so sliding along the top edge away from the
        // notch never changes `over` — reveal would never see the move.
        reveal?.evaluate(notchRect: rect)

        let over = rect.contains(NSEvent.mouseLocation)

        // ignoresMouseEvents and hoverChanged have separate dedup: reveal can
        // flip interactivity while `over` stays put (band hover away from the
        // rect, HUD-driven reveal), so both must be evaluated independently
        // on every call rather than sharing one early return.
        let interactive = over && (reveal?.allowsInteraction ?? true)
        if interactive != wasInteractive {
            wasInteractive = interactive
            panel?.ignoresMouseEvents = !interactive
        }
        if over != isOverNotch {
            isOverNotch = over
            model.hoverChanged(over)
        }
    }
}
