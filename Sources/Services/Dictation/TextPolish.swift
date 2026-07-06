import Foundation

/// Deterministic, on-device transcript tidy-up: applies the user's vocabulary
/// casing and optional sentence capitalization. No network, no model.
enum TextPolish {
    static func apply(_ text: String, dictionary: [String], capitalize: Bool) -> String {
        var result = text
        result = applyVocabulary(result, terms: dictionary)
        if capitalize { result = capitalizeSentences(result) }
        return result
    }

    /// Rewrites each dictionary term to its exact stored casing wherever it
    /// appears (case-insensitive match, whole-word). Longest terms win first so
    /// multi-word entries take precedence.
    private static func applyVocabulary(_ text: String, terms: [String]) -> String {
        var result = text
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: term))
        }
        return result
    }

    /// Capitalizes the first letter of the text and after sentence-ending
    /// punctuation.
    private static func capitalizeSentences(_ text: String) -> String {
        var chars = Array(text)
        var capitalizeNext = true
        for i in chars.indices {
            let c = chars[i]
            if capitalizeNext, c.isLetter {
                chars[i] = Character(c.uppercased())
                capitalizeNext = false
            } else if ".!?".contains(c) {
                capitalizeNext = true
            } else if !c.isWhitespace {
                capitalizeNext = false
            }
        }
        return String(chars)
    }
}
