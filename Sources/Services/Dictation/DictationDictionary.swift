import Foundation
import Combine

/// User's custom vocabulary: terms that should be rewritten to an exact casing
/// wherever they appear in a transcript ("github" → "GitHub", "kyc" → "KYC").
@MainActor
final class DictationDictionary: ObservableObject {
    static let shared = DictationDictionary()

    @Published private(set) var terms: [String]

    private let defaults = UserDefaults.standard
    private let key = "dictation.dictionary"

    init() {
        terms = defaults.stringArray(forKey: key) ?? []
    }

    func add(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        terms.append(trimmed)
        save()
    }

    func remove(_ term: String) {
        terms.removeAll { $0 == term }
        save()
    }

    private func save() {
        defaults.set(terms, forKey: key)
    }
}
