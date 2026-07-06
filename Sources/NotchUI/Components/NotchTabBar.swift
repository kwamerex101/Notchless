import SwiftUI

/// The slim tab strip along the very top of the expanded notch. To stay clear of
/// the hardware notch (centred), it shows only a three-glyph window on the LEFT —
/// previous · active · next, the active one at full brightness and its two
/// neighbours dimmed — and a persistent battery percentage on the RIGHT. The
/// hardware notch sits in the empty gap between them. Tapping a neighbour selects
/// it, sliding the window by one.
struct NotchTabBar: View {
    let activities: [NotchActivity]
    let active: NotchActivity
    let battery: BatteryInfo?
    var onSelect: (NotchActivity) -> Void
    /// Width of the hardware notch — reserved as the centre gap so the glyphs
    /// (left) and battery (right) stay in the wings, clear of the camera.
    var notchWidth: CGFloat = 200

    /// Reserved height of the strip.
    static let height: CGFloat = 22

    /// Up to three pages centred on the active one — [prev, active, next],
    /// wrapping around the carousel. Shows all when there are three or fewer.
    private var window: [NotchActivity] {
        guard let i = activities.firstIndex(of: active) else { return [active] }
        let n = activities.count
        guard n > 3 else { return activities }
        let prev = activities[(i - 1 + n) % n]
        let next = activities[(i + 1) % n]
        return [prev, active, next]
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(window, id: \.self) { activity in
                Image(systemName: activity.tabGlyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(activity == active ? 1.0 : 0.35)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(activity) }
                    .accessibilityLabel(Text(activity.tabLabel))
                    .accessibilityAddTraits(activity == active ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: notchWidth + 12)
            if let battery {
                Text("\(battery.level)%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .animation(NotchViewModel.morph, value: active)
    }
}
