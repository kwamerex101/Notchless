import Foundation
import Combine

/// A saved text expansion: say the trigger, get the expansion.
struct DictationSnippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

/// Text expansions applied to a finished transcript ("my email" → an address).
@MainActor
final class DictationSnippets: ObservableObject {
    static let shared = DictationSnippets()

    @Published private(set) var snippets: [DictationSnippet] = []

    private let defaults = UserDefaults.standard
    private let key = "dictation.snippets"

    private init() { load() }

    func add(trigger: String, expansion: String) {
        let t = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !e.isEmpty else { return }
        snippets.append(DictationSnippet(trigger: t, expansion: e))
        save()
    }

    func remove(_ snippet: DictationSnippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    /// Replaces each trigger phrase (whole-phrase, case-insensitive) with its
    /// expansion. Longest triggers win first.
    func expand(_ text: String) -> String {
        var result = text
        for snippet in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: snippet.trigger) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: snippet.expansion))
        }
        return result
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DictationSnippet].self, from: data) else { return }
        snippets = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snippets) { defaults.set(data, forKey: key) }
    }
}
