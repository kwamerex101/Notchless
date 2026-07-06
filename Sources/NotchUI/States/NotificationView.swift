import SwiftUI

/// A transient notch banner (charging, Bluetooth, Focus, network…): a tinted
/// icon chip on the left, title/subtitle, and an optional trailing status.
/// Original design in the Dynamic Island idiom.
struct NotificationView: View {
    let note: TransientNotification
    let metrics: NotchMetrics

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            iconChip
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                if let sub = note.subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing = note.trailingText {
                Text(trailing)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(note.tint == .white ? .white : note.tint)
            }
        }
        .padding(.top, metrics.notchHeight + 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            withAnimation(NotchMotion.quick) { appeared = true }
        }
    }

    private var iconChip: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(note.tint.gradient)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: note.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: note.tint.opacity(0.5), radius: 5)
            .scaleEffect(appeared ? 1 : 0.6)
    }
}
