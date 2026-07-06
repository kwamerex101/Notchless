import Foundation

/// Safe, formatting-only spoken commands applied to a transcript. Deliberately
/// excludes ListenToMe's shell/file commands — nothing here runs code or writes
/// files, so it's safe to leave on.
enum SpokenCommands {
    static func apply(_ text: String) -> String {
        var result = text

        // Spoken formatting → real characters (case-insensitive, whole phrase).
        let replacements: [(String, String)] = [
            ("new paragraph", "\n\n"),
            ("new line", "\n"),
            ("open quote", "\""),
            ("close quote", "\""),
        ]
        for (phrase, replacement) in replacements {
            result = replace(phrase, with: replacement, in: result)
        }

        // "scratch that" / "delete that" removes the preceding sentence.
        for phrase in ["scratch that", "delete that"] {
            while let range = result.range(of: phrase, options: [.caseInsensitive]) {
                let before = String(result[..<range.lowerBound])
                let trimmed = dropLastSentence(before)
                result = trimmed + result[range.upperBound...]
            }
        }

        return result
            .replacingOccurrences(of: " \n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ phrase: String, with replacement: String, in text: String) -> String {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    private static func dropLastSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let idx = trimmed.range(of: "[.!?]", options: [.regularExpression, .backwards])?.upperBound {
            return String(trimmed[..<idx]) + " "
        }
        return ""
    }
}
