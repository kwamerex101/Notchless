import Foundation

/// Decides whether a transcript is already clean enough to skip the (slow,
/// possibly network) polish step in Smart mode. Errs toward cleaning when
/// unsure — a false "needs cleanup" just spends a little time.
enum CleanupGate {
    /// Common spoken fillers whose presence suggests the text needs tidying.
    private static let fillers = [
        "um", "uh", "erm", "you know", "i mean", "like like", "sort of", "kind of",
    ]

    /// Returns true if the text looks like it would benefit from cleanup.
    static func needsCleanup(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()

        // Fillers present → clean.
        if fillers.contains(where: { lower.contains(" \($0) ") || lower.hasPrefix("\($0) ") }) {
            return true
        }
        // Repeated adjacent words ("the the") → clean.
        if trimmed.range(of: #"\b(\w+)\s+\1\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        // No terminal punctuation on a multi-word utterance → clean.
        let words = trimmed.split(separator: " ")
        if words.count > 3, let last = trimmed.unicodeScalars.last,
           !CharacterSet(charactersIn: ".!?").contains(last) {
            return true
        }
        // Lowercase first letter → clean.
        if let first = trimmed.first, first.isLetter, first.isLowercase {
            return true
        }
        return false
    }
}
