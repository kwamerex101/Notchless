import SwiftUI

/// Minimal, self-contained HUD pill rendered inside `FloatingHUDPanel`. The
/// notch's `HUDView` has notch-specific padding/anchoring baked in, so it
/// can't be reused directly here.
/// TODO(P4-styles): replace with proper Classic/iOS/Circular floating styles.
struct FloatingHUDContentView: View {
    let kind: HUDKind
    let options: HUDOptions

    static let estimatedSize = CGSize(width: 260, height: 44)

    private var barLevel: Double {
        if case let .sound(_, muted) = kind, muted, options.showMuteAsEmpty {
            return 0
        }
        return kind.level
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18)

            if case .sound = kind, options.showOutputDevice {
                Image(systemName: AudioOutputService.shared.currentOutputSymbol())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 16)
            }

            HUDBar(level: barLevel)
                .frame(width: 120, height: 6)

            if options.showPercentageLabel {
                Text("\(Int((kind.level * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black))
        .foregroundStyle(.white)
    }
}
