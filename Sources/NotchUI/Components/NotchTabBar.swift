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

    /// Reserved height of the strip. Spec §2 "Wings tab strip".
    static let height: CGFloat = 32

    /// The panel must be at least this wide for the strip to clear the centred
    /// hardware notch: the left window (leading pad + three glyph buttons + gaps)
    /// and the right battery each need a wing beside the cutout.
    static func minPanelWidth(notchWidth: CGFloat) -> CGFloat {
        let wing: CGFloat = 14 + (3 * 18) + (2 * 12) + 8   // pad + 3 glyphs + 2 gaps + margin = 100
        return notchWidth + wing * 2
    }

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
                Button { onSelect(activity) } label: {
                    // Glyph is 12x12 per spec; the button keeps the original
                    // 18x18 hit target so tapping a neighbour doesn't shrink.
                    ZStack {
                        Image(systemName: activity.tabGlyph)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NotchTheme.textPrimary)
                            .opacity(activity == active ? 1.0 : 0.35)
                            .frame(width: 12, height: 12)
                        if activity == active {
                            // 3x3 dot, centred 2pt below the glyph.
                            Circle()
                                .fill(NotchTheme.textPrimary)
                                .frame(width: 3, height: 3)
                                .offset(y: 9.5)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NotchButtonStyle())
                .accessibilityLabel(Text(activity.tabLabel))
                .accessibilityAddTraits(activity == active ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: notchWidth + 12)
            if let battery {
                Text("\(battery.level)%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentTransition(.numericText())
                    .animation(.default, value: battery.level)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .animation(NotchViewModel.morph, value: active)
    }
}
