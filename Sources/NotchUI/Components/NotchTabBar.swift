import SwiftUI

/// The slim tab strip along the top of the expanded notch. Left: one monochrome
/// glyph per carousel page (active at full brightness, others dimmed). Right: a
/// persistent battery-percentage status. Tapping a glyph selects that page.
struct NotchTabBar: View {
    let activities: [NotchActivity]
    let active: NotchActivity
    let battery: BatteryInfo?
    var onSelect: (NotchActivity) -> Void

    /// Reserved height of the strip; Task 4 grows the panel by this amount.
    static let height: CGFloat = 22

    var body: some View {
        HStack(spacing: 10) {
            ForEach(activities, id: \.self) { activity in
                Image(systemName: activity.tabGlyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(activity == active ? 1.0 : 0.4)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(activity) }
                    .accessibilityLabel(Text(activity.tabLabel))
                    .accessibilityAddTraits(activity == active ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 8)
            if let battery {
                Text("\(battery.level)%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .animation(NotchViewModel.morph, value: active)
    }
}
