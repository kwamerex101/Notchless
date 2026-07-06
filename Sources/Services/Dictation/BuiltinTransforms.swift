import Foundation

/// Deterministic text fix-ups applied to every transcript (when "Smart
/// formatting" is on): spoken operators like "C plus plus" → "C++", semver
/// joins, and collapsing accidental double-speak ("the the" → "the").
enum BuiltinTransforms {
    static func apply(_ text: String) -> String {
        var result = text
        result = spokenOperators(result)
        result = semver(result)
        result = collapseRepeats(result)
        return result
    }

    // MARK: - Spoken operators

    /// Longest phrases first so "plus plus" wins before "plus".
    private static let operators: [(phrase: String, symbol: String)] = [
        ("c plus plus", "C++"),
        ("c sharp", "C#"),
        ("plus plus", "++"),
        ("minus minus", "--"),
    ]

    private static func spokenOperators(_ text: String) -> String {
        var result = text
        for (phrase, symbol) in operators {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
            result = result.replacingOccurrences(
                of: pattern, with: symbol,
                options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    // MARK: - Semver

    /// "1 dot 0 dot 29" → "1.0.29" and "1.0.29 plus 230" → "1.0.29+230".
    private static func semver(_ text: String) -> String {
        var result = text
        // number "dot" number → number.number (repeatable for x.y.z)
        for _ in 0..<3 {
            result = result.replacingOccurrences(
                of: #"(\d)\s+dot\s+(\d)"#, with: "$1.$2",
                options: [.regularExpression, .caseInsensitive])
        }
        // version "plus" build → version+build
        result = result.replacingOccurrences(
            of: #"(\d)\s+plus\s+(\d)"#, with: "$1+$2",
            options: [.regularExpression, .caseInsensitive])
        return result
    }

    // MARK: - Collapse repeats

    /// Collapses an adjacent duplicate word ("the the" → "the"). Skips
    /// capitalized words to avoid touching proper nouns / sentence starts, and a
    /// small allowlist of legitimately-doubled words.
    private static let legitimateDoubles: Set<String> = ["had", "that", "is", "who", "so"]

    private static func collapseRepeats(_ text: String) -> String {
        let pattern = try? NSRegularExpression(pattern: #"\b([a-z]+)\s+\1\b"#)
        guard let pattern else { return text }
        let ns = text as NSString
        var result = text
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        for match in matches {
            let word = ns.substring(with: match.range(at: 1)).lowercased()
            if legitimateDoubles.contains(word) { continue }
            let full = ns.substring(with: match.range)
            let single = String(full.split(separator: " ").first ?? "")
            if let r = Range(match.range, in: result) {
                result.replaceSubrange(r, with: single)
            }
        }
        return result
    }
}
