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

    /// Removes chat-template control tokens an instruct/local model can leak into
    /// its output — e.g. the ChatML stop marker `<|im_end|>` or Gemma's
    /// `<end_of_turn>`. Cuts the text at the first such marker (nothing a user
    /// dictates contains these) and trims. Applied to the cleanup stage's output
    /// so every backend is defended, not just the on-device one.
    static func stripModelTokens(_ text: String) -> String {
        var result = text
        // ChatML-style tokens all begin "<|" — covers <|im_end|>, <|im_start|>,
        // <|endoftext|>, <|eot_id|>, and timeout-truncated variants like "<|im_en".
        if let r = result.range(of: "<|") {
            result = String(result[..<r.lowerBound])
        }
        // Gemma / Llama / sentinel end markers.
        for marker in ["<end_of_turn>", "<start_of_turn>", "</s>", "<eos>", "<bos>"] {
            if let r = result.range(of: marker) {
                result = String(result[..<r.lowerBound])
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
