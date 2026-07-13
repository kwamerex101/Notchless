import SwiftUI

/// Dispatches to the floating HUD style rendered inside `FloatingHUDPanel`.
/// `.notch` never reaches here — `HUDPresenter` routes it to the notch — but
/// this switch is total (falls back to the iOS style) so the view stays safe
/// if that invariant is ever violated upstream.
struct FloatingHUDContentView: View {
    let kind: HUDKind
    let options: HUDOptions
    var style: HUDStyle = .ios
    var indicator: HUDIndicator = .dot
    var accent: Color?

    static func estimatedSize(for style: HUDStyle) -> CGSize {
        switch style {
        case .notch, .ios: return IOSHUDView.estimatedSize
        case .classic: return ClassicHUDView.estimatedSize
        case .circular: return CircularHUDView.estimatedSize
        }
    }

    var body: some View {
        switch style {
        case .notch, .ios:
            IOSHUDView(kind: kind, options: options, accent: accent)
        case .classic:
            ClassicHUDView(kind: kind, options: options, accent: accent)
        case .circular:
            CircularHUDView(kind: kind, options: options, accent: accent, indicator: indicator)
        }
    }
}
