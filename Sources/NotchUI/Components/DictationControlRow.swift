import SwiftUI

/// The recording panel's bottom row: where the text will land (leading), the
/// elapsed time (center-trailing, rendered natively so it never republishes),
/// and an `esc` keycap that cancels the session.
struct DictationControlRow: View {
    var modeName: String? = nil
    var target: DictationTarget?
    var startedAt: Date?
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let modeName {
                Text(modeName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                Text("·").foregroundStyle(NotchTheme.textTertiary)
            }

            if let target, !target.name.isEmpty {
                HStack(spacing: 4) {
                    if let icon = target.icon {
                        Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                    }
                    Text(target.name)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if let startedAt {
                Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchTheme.textSecondary)
                    .fixedSize()
            }

            Button(action: onCancel) {
                HStack(spacing: 4) {
                    Text("esc")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(NotchTheme.chip))
                        .foregroundStyle(NotchTheme.textPrimary)
                    Text("Cancel")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}
