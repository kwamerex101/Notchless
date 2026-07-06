import Foundation

/// Learns from manual corrections: when the same single-word substitution is
/// made repeatedly (default 3×), the corrected word is promoted into the custom
/// dictionary so future transcripts adopt it automatically.
@MainActor
final class CorrectionMiner {
    static let shared = CorrectionMiner()

    private let defaults = UserDefaults.standard
    private let key = "dictation.correctionCounts"
    private let threshold = 3

    /// Diffs the two texts and counts single-word substitutions.
    func record(heard: String, corrected: String) {
        let before = heard.split(separator: " ").map(String.init)
        let after = corrected.split(separator: " ").map(String.init)
        // Only mine when the edit is a set of aligned word swaps (same length).
        guard before.count == after.count else { return }

        var counts = loadCounts()
        for (old, new) in zip(before, after) where old.lowercased() != new.lowercased() {
            let cleanNew = new.trimmingCharacters(in: .punctuationCharacters)
            guard cleanNew.rangeOfCharacter(from: .letters) != nil else { continue }
            let key = "\(old.lowercased())→\(cleanNew)"
            let count = (counts[key] ?? 0) + 1
            counts[key] = count
            if count >= threshold {
                DictationDictionary.shared.add(cleanNew)
                counts[key] = nil   // promoted; stop tracking
            }
        }
        saveCounts(counts)
    }

    private func loadCounts() -> [String: Int] {
        defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    private func saveCounts(_ counts: [String: Int]) {
        defaults.set(counts, forKey: key)
    }
}
