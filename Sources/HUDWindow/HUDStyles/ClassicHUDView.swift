import SwiftUI

/// Compact dark rounded pill: icon + a slim bar. The tightest-footprint
/// floating style, closest in spirit to the old Boom2/Growl OSDs.
/// on-device: tune visuals
struct ClassicHUDView: View {
    let kind: HUDKind
    let options: HUDOptions
    let accent: Color?

    static let estimatedSize = CGSize(width: 200, height: 36)

    private var barLevel: Double {
        if case let .sound(_, muted) = kind, muted, options.showMuteAsEmpty {
            return 0
        }
        return kind.level
    }

    private var fillColor: Color { accent ?? .white }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 14)

            HUDBar(level: barLevel, color: fillColor)
                .frame(width: 100, height: 4)

            if options.showPercentageLabel {
                Text("\(Int((kind.level * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black))
        .foregroundStyle(.white)
    }
}
