import Foundation

enum TranscriptMerger {
    /// Interleave "You" and remote segments into one time-ordered transcript.
    /// Empty/whitespace-only segments are dropped; ties break with "You" first.
    static func merge(you: [TranscriptSegment],
                      remote: [TranscriptSegment],
                      duration: TimeInterval) -> MeetingTranscript {
        let all = (you + remote)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { a, b in
                if a.start != b.start { return a.start < b.start }
                return isYou(a.speaker) && !isYou(b.speaker)
            }
        return MeetingTranscript(segments: all, duration: duration)
    }

    private static func isYou(_ s: Speaker) -> Bool {
        if case .you = s { return true }
        return false
    }
}
