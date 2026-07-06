import SwiftUI

/// Transient notification content (battery, connectivity, focus…): tinted icon
/// on the left, title/subtitle, optional trailing text (see PLAN.md §1.2).
struct NotificationView: View {
    let note: TransientNotification
    let metrics: NotchMetrics

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: note.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(note.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                if let sub = note.subtitle {
                    Text(sub).font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing = note.trailingText {
                Text(trailing).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, metrics.notchHeight + 4)
        .padding(.horizontal, 28)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
