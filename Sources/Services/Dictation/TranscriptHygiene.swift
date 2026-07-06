import Foundation

/// Strips non-speech markers that ASR engines sometimes emit (e.g.
/// "[BLANK_AUDIO]", "(silence)") before the text is polished or delivered.
enum TranscriptHygiene {
    /// Bracketed markers like [BLANK_AUDIO], (SILENCE), [ Music ].
    private static let markerPattern = try? NSRegularExpression(
        pattern: #"[\[(]\s*(blank_audio|silence|music|noise|inaudible|no speech|background noise)\s*[\])]"#,
        options: [.caseInsensitive])

    static func clean(_ text: String) -> String {
        var result = text
        if let markerPattern {
            let range = NSRange(result.startIndex..., in: result)
            result = markerPattern.stringByReplacingMatches(in: result, range: range, withTemplate: "")
        }
        // Collapse the whitespace the removals leave behind.
        result = result.replacingOccurrences(
            of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
