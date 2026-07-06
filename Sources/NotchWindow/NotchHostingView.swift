import AppKit
import SwiftUI

/// Hosts the notch UI but only claims mouse events over the current shape
/// rect, so the transparent remainder of the panel stays click-through.
final class NotchHostingView: NSHostingView<NotchRootView> {
    weak var model: NotchViewModel?
    var metrics: NotchMetrics
    /// Called for horizontal swipe-to-seek on the media pane.
    var onMediaCommand: ((MediaCommand) -> Void)?

    // Two-finger swipe accumulation (one action fires per gesture).
    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    private var swipeFired = false

    init(rootView: NotchRootView, model: NotchViewModel, metrics: NotchMetrics) {
        self.model = model
        self.metrics = metrics
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: NotchRootView) { fatalError() }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Two-finger trackpad swipes over the notch: vertical opens (down) /
    /// closes (up); horizontal seeks the media pane by ±10s. One action per
    /// gesture, then it waits for the next.
    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas,
              SettingsStore.shared.swipeGesturesEnabled else { super.scrollWheel(with: event); return }

        if event.phase.contains(.began) {
            swipeX = 0; swipeY = 0; swipeFired = false
        }
        swipeX += event.scrollingDeltaX
        swipeY += event.scrollingDeltaY

        let threshold: CGFloat = 28
        if !swipeFired {
            if abs(swipeY) > abs(swipeX), abs(swipeY) > threshold {
                swipeFired = true
                let openIt = swipeY < 0   // fingers move down → open
                MainActor.assumeIsolated { openIt ? model?.tapped() : model?.collapse() }
            } else if abs(swipeX) > threshold {
                swipeFired = true
                MainActor.assumeIsolated {
                    // In Auto with something live, swipe pages through the
                    // activities (playing / calendar / stats / …); otherwise it
                    // scrubs the current track.
                    if SettingsStore.shared.idleActivity == .auto, !(model?.liveActivities.isEmpty ?? true) {
                        model?.cycleLiveActivity()
                    } else {
                        seek(forward: swipeX < 0)
                    }
                }
            }
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            swipeFired = false
        }
    }

    @MainActor
    private func seek(forward: Bool) {
        guard SettingsStore.shared.swipeToSeek, let info = model?.nowPlaying else { return }
        let target = max(0, min(info.duration, info.elapsed + (forward ? 10 : -10)))
        onMediaCommand?(.seek(target))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let model else { return nil }
        let sizing = NotchSizing.size(for: model.content, metrics: metrics)
        let w = bounds.width, h = bounds.height
        let pad: CGFloat = 4

        // The shape is drawn top-centre. `convert(_:from:)` yields `local` in this
        // view's own space, which is flipped (NSHostingView.isFlipped == true) —
        // so the visual top is y ≈ 0. Compute the interactive band flip-safely so
        // everything outside it stays click-through.
        let local = superview.map { convert(point, from: $0) } ?? point
        let minX = (w - sizing.width) / 2 - pad
        let maxX = (w + sizing.width) / 2 + pad
        let bandTop: CGFloat = isFlipped ? -pad : h - sizing.height - pad
        let bandBottom: CGFloat = isFlipped ? sizing.height + pad : h + pad

        let inside = local.x >= minX && local.x <= maxX
            && local.y >= bandTop && local.y <= bandBottom
        HitLog.log(inside: inside, local: local, bounds: bounds.size, flipped: isFlipped,
                   band: CGRect(x: minX, y: min(bandTop, bandBottom),
                                width: maxX - minX, height: abs(bandBottom - bandTop)),
                   content: model.content)
        return inside ? super.hitTest(point) : nil
    }
}

/// Gated hit-test diagnostics (set DI_DEBUG_HITTEST). Logs the band once per
/// content change and every capture, to /tmp/notchless_hit.log.
enum HitLog {
    nonisolated(unsafe) static var lastContent = ""
    static let on = ProcessInfo.processInfo.environment["DI_DEBUG_HITTEST"] != nil

    static func log(inside: Bool, local: CGPoint, bounds: CGSize, flipped: Bool,
                    band: CGRect, content: NotchContent) {
        guard on else { return }
        let key = "\(content)"
        var lines: [String] = []
        if key != lastContent {
            lastContent = key
            lines.append("CONTENT \(key) bounds=\(Int(bounds.width))x\(Int(bounds.height)) flipped=\(flipped) band=(\(Int(band.minX)),\(Int(band.minY)),\(Int(band.width))x\(Int(band.height)))")
        }
        if inside {
            lines.append("CAPTURE local=(\(Int(local.x)),\(Int(local.y))) content=\(key)")
        }
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: "\n") + "\n"
        let url = URL(fileURLWithPath: "/tmp/notchless_hit.log")
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }
}
