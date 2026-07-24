import SwiftUI

/// A single centered line of the live transcript. Head-truncation keeps the
/// newest words on screen (an ellipsis clips older words when it overflows).
/// Empty text shows a calm placeholder (which is also the permanent state for
/// engines without partials, e.g. Parakeet).
struct LiveTranscriptView: View {
    var text: String
    var reduceMotion: Bool

    var body: some View {
        Text(text.isEmpty ? "Listening…" : text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(text.isEmpty ? NotchTheme.textSecondary : NotchTheme.textPrimary.opacity(0.95))
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(NotchMotion.animation(NotchMotion.transcriptWord, reduceMotion: reduceMotion), value: text)
    }
}
