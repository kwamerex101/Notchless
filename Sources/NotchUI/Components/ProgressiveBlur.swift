import SwiftUI

/// A behind-window blur, gradient-masked so it's strongest at the top and fades
/// downward — approximating Alcove's progressive blur around an expanded panel
/// (see PLAN.md §1.3). True variable blur needs a private CAFilter; this
/// gradient-masked material is a close, App-Store-safe approximation.
struct ProgressiveBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true

        let mask = CAGradientLayer()
        mask.colors = [
            NSColor.black.cgColor,
            NSColor.black.withAlphaComponent(0.6).cgColor,
            NSColor.clear.cgColor,
        ]
        mask.locations = [0, 0.6, 1]
        mask.startPoint = CGPoint(x: 0.5, y: 1)   // top (flipped layer space)
        mask.endPoint = CGPoint(x: 0.5, y: 0)     // bottom
        view.layer?.mask = mask
        context.coordinator.mask = mask
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        context.coordinator.mask?.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var mask: CAGradientLayer?
    }
}
