import SwiftUI

/// A single tail-anchored line of the live transcript. Head-truncation keeps the
/// newest words on screen; a leading gradient mask fades older words out so the
/// line never reads as clipped. Empty text shows a calm placeholder (which is
/// also the permanent state for engines without partials, e.g. Parakeet).
struct LiveTranscriptView: View {
    var text: String
    var reduceMotion: Bool

    var body: some View {
        Text(text.isEmpty ? "Listening…" : text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(text.isEmpty ? 0.4 : 0.85))
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mask(leadingFade)
            .animation(NotchMotion.animation(NotchMotion.transcriptWord, reduceMotion: reduceMotion), value: text)
    }

    private var leadingFade: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.0),
            .init(color: .black, location: 0.14),
            .init(color: .black, location: 1.0),
        ], startPoint: .leading, endPoint: .trailing)
    }
}
