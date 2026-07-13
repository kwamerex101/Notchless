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

    /// Phase 5 click-drag callback: `(fraction 0...1, isEnded)`. Set only
    /// when `HUDPresenter` decides the floating panel should be interactive
    /// (`clickDragToChangeValue`); the drag gesture below is attached only
    /// when this is non-nil, so the panel stays passthrough otherwise.
    var onDragFraction: ((Double, Bool) -> Void)? = nil

    static func estimatedSize(for style: HUDStyle) -> CGSize {
        switch style {
        case .notch, .ios: return IOSHUDView.estimatedSize
        case .classic: return ClassicHUDView.estimatedSize
        case .circular: return CircularHUDView.estimatedSize
        }
    }

    var body: some View {
        GeometryReader { geo in
            if onDragFraction != nil {
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: geo.size))
            } else {
                content
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .frame(width: Self.estimatedSize(for: style).width, height: Self.estimatedSize(for: style).height)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .notch, .ios:
            IOSHUDView(kind: kind, options: options, accent: accent)
        case .classic:
            ClassicHUDView(kind: kind, options: options, accent: accent)
        case .circular:
            CircularHUDView(kind: kind, options: options, accent: accent, indicator: indicator)
        }
    }

    /// Only attached (has an effect) when `onDragFraction` is set; returns a
    /// no-op gesture otherwise so non-interactive panels behave exactly as
    /// before.
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let onDragFraction else { return }
                onDragFraction(fraction(for: value.location, in: size), false)
            }
            .onEnded { value in
                guard let onDragFraction else { return }
                onDragFraction(fraction(for: value.location, in: size), true)
            }
    }

    private func fraction(for location: CGPoint, in size: CGSize) -> Double {
        style == .circular
            ? HUDValueMapper.dialFraction(location: location, in: size)
            : HUDValueMapper.horizontalFraction(x: location.x, width: size.width)
    }
}
