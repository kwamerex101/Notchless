import SwiftUI

/// A transient notch banner (charging, Bluetooth, Focus, network…): a tinted
/// icon chip on the left, title/subtitle, and an optional trailing status.
/// Original design in the Dynamic Island idiom.
struct NotificationView: View {
    let note: TransientNotification
    let metrics: NotchMetrics

    @State private var appeared = false

    /// `NotificationsController` already passes the exact flat-dark semantic
    /// token for each banner (`NotchTheme.positive`/`.link`/`.focus`/`.warning`,
    /// spec §1 "Semantic colour") — trust it directly rather than re-deriving
    /// it from a system-color guess. A prior version of this switched on
    /// system colors like `.blue`/`.green`; once the caller moved to passing
    /// `NotchTheme.*` values (which aren't `==` to the system colors they
    /// resemble), every case silently missed and fell through to the
    /// `default` neutral tint — losing the banner's color entirely.
    private var semanticTint: Color { note.tint }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            iconChip
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary).lineLimit(1)
                if let sub = note.subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        // Spec §3 "Notification banners": 496x70, radius 20, content
        // bottom-aligned, padding 0/24/14.
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear {
            withAnimation(NotchMotion.quick) { appeared = true }
        }
    }

    /// Trailing status: the formatted string when the caller supplied one
    /// (charging %, etc.), styled in the semantic tint; otherwise a
    /// decorative close glyph, matching the Focus/network rows in the spec.
    @ViewBuilder
    private var trailing: some View {
        if let trailingText = note.trailingText {
            Text(trailingText)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(semanticTint)
        } else {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary.opacity(0.4))
                .frame(width: 11, height: 11)
        }
    }

    private var iconChip: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(semanticTint.opacity(0.16))
            .frame(width: 30, height: 30)
            .overlay(
                Image(systemName: note.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(semanticTint)
            )
            .scaleEffect(appeared ? 1 : 0.6)
    }
}
