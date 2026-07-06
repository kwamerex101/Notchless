import AppKit
import Combine

/// Makes the notch panel genuinely click-through everywhere except over the
/// notch itself. Returning nil from `hitTest` does NOT pass clicks to the app
/// below — the panel swallows them — so instead we toggle
/// `panel.ignoresMouseEvents` based on the cursor position. Global + local
/// mouse monitors (mouse events need no special permission) tell us when the
/// cursor enters/leaves the current notch shape, and we also drive the notch's
/// hover state from the same signal.
@MainActor
final class NotchMouseTracker {
    private weak var panel: NotchPanel?
    private let model: NotchViewModel
    var metrics: NotchMetrics { didSet { rectDirty = true } }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isOverNotch = false

    /// Cached interactive rect + a dirty flag, so we don't recompute `NotchSizing`
    /// (a big switch) on every system-wide mouse move — only after the notch's
    /// content actually changes shape.
    private var cachedRect: CGRect = .zero
    private var rectDirty = true
    private var contentObserver: AnyCancellable?

    init(panel: NotchPanel, model: NotchViewModel, metrics: NotchMetrics) {
        self.panel = panel
        self.model = model
        self.metrics = metrics
    }

    func start() {
        panel?.ignoresMouseEvents = true  // pass-through by default

        // Any model change may resize the notch; mark the rect stale so the next
        // evaluate() recomputes it once. Cheap bool flip vs. per-move sizing.
        contentObserver = model.objectWillChange.sink { [weak self] _ in
            self?.rectDirty = true
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
            cachedRect = NotchSizing.screenBand(for: model.content, metrics: metrics, pad: 6)
            rectDirty = false
        }
        return cachedRect
    }

    private func evaluate() {
        let over = currentRect().contains(NSEvent.mouseLocation)
        guard over != isOverNotch else { return }
        isOverNotch = over
        panel?.ignoresMouseEvents = !over
        model.hoverChanged(over)
    }
}
