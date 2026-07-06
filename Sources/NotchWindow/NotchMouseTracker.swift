import AppKit

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
    var metrics: NotchMetrics

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isOverNotch = false

    init(panel: NotchPanel, model: NotchViewModel, metrics: NotchMetrics) {
        self.panel = panel
        self.model = model
        self.metrics = metrics
    }

    func start() {
        panel?.ignoresMouseEvents = true  // pass-through by default

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
    }

    /// Screen-space rect (bottom-left origin, matching `NSEvent.mouseLocation`)
    /// of the current notch shape, with a little slack for easy targeting.
    private func notchRect() -> CGRect {
        let sizing = NotchSizing.size(for: model.content, metrics: metrics)
        let pad: CGFloat = 6
        return CGRect(
            x: metrics.notchCenterX - sizing.width / 2 - pad,
            y: metrics.screenTopY - sizing.height - pad,
            width: sizing.width + pad * 2,
            height: sizing.height + pad * 2
        )
    }

    private func evaluate() {
        let over = notchRect().contains(NSEvent.mouseLocation)
        guard over != isOverNotch else { return }
        isOverNotch = over
        panel?.ignoresMouseEvents = !over
        model.hoverChanged(over)
    }
}
