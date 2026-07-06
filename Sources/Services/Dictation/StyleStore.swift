import Foundation
import Combine

/// The writing tone learned for a given app.
enum StyleTone: String, Codable, CaseIterable, Identifiable {
    case none, formal, casual, code, markdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Neutral"
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .code: return "Code"
        case .markdown: return "Markdown"
        }
    }

    var promptHint: String {
        switch self {
        case .none: return ""
        case .formal: return "The user writes formally here — use complete sentences and avoid slang."
        case .casual: return "The user writes casually here — keep it relaxed and conversational."
        case .code: return "The user writes code/technical text here — preserve identifiers and symbols."
        case .markdown: return "The user writes Markdown here — keep Markdown structure intact."
        }
    }
}

/// Learns a per-app tone from the transcripts delivered into each app. After
/// `sampleThreshold` samples a tone is suggested; the user can accept, change,
/// or dismiss it in the Style pane. Applied tones augment the cleanup prompt.
@MainActor
final class StyleStore: ObservableObject {
    static let shared = StyleStore()

    struct AppStyle: Codable, Identifiable {
        var bundleID: String
        var sampleCount: Int
        var signals: [String: Int]      // tone.rawValue → accumulated score
        var acceptedTone: StyleTone?
        var suggestedTone: StyleTone?
        var dismissed: Bool
        var id: String { bundleID }
    }

    @Published private(set) var styles: [String: AppStyle] = [:]

    private let defaults = UserDefaults.standard
    private let key = "dictation.appStyles"
    private let sampleThreshold = 20

    init() { load() }

    /// The prompt hint to apply for an app right now (accepted tone only).
    func promptHint(for bundleID: String) -> String {
        styles[bundleID]?.acceptedTone?.promptHint ?? ""
    }

    /// Feed a delivered transcript to update the learned signals for its app.
    func observe(text: String, bundleID: String) {
        guard !bundleID.isEmpty else { return }
        var style = styles[bundleID] ?? AppStyle(
            bundleID: bundleID, sampleCount: 0, signals: [:],
            acceptedTone: nil, suggestedTone: nil, dismissed: false)
        style.sampleCount += 1
        let tone = Self.dominantSignal(in: text)
        if tone != .none {
            style.signals[tone.rawValue, default: 0] += 1
        }
        // Suggest once enough samples accumulate and nothing's been decided.
        if style.sampleCount >= sampleThreshold, style.acceptedTone == nil, !style.dismissed,
           let top = style.signals.max(by: { $0.value < $1.value })?.key,
           let suggested = StyleTone(rawValue: top), suggested != .none {
            style.suggestedTone = suggested
        }
        styles[bundleID] = style
        save()
    }

    func accept(_ bundleID: String, tone: StyleTone) {
        guard var style = styles[bundleID] else { return }
        style.acceptedTone = tone
        style.suggestedTone = nil
        styles[bundleID] = style
        save()
    }

    func dismissSuggestion(_ bundleID: String) {
        guard var style = styles[bundleID] else { return }
        style.suggestedTone = nil
        style.dismissed = true
        styles[bundleID] = style
        save()
    }

    func revert(_ bundleID: String) {
        guard var style = styles[bundleID] else { return }
        style.acceptedTone = nil
        style.dismissed = false
        styles[bundleID] = style
        save()
    }

    // MARK: - Feature detection

    private static func dominantSignal(in text: String) -> StyleTone {
        let lower = text.lowercased()
        var scores: [StyleTone: Int] = [:]

        if text.range(of: #"[{}();]|[a-z][A-Z]|\w_\w|`"#, options: .regularExpression) != nil {
            scores[.code, default: 0] += 2
        }
        if text.range(of: #"(^|\n)\s*[#\-*]\s|\[.+\]\(.+\)"#, options: .regularExpression) != nil {
            scores[.markdown, default: 0] += 2
        }
        if lower.range(of: #"\b(lol|haha|yeah|gonna|wanna|kinda)\b|!{1,}"#, options: .regularExpression) != nil {
            scores[.casual, default: 0] += 1
        }
        // Long sentences with no contractions read as formal.
        let words = text.split(separator: " ").count
        if words > 15, text.range(of: #"n't|'ll|'re|'ve"#, options: .regularExpression) == nil {
            scores[.formal, default: 0] += 1
        }
        return scores.max(by: { $0.value < $1.value })?.key ?? .none
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: AppStyle].self, from: data) else { return }
        styles = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(styles) else { return }
        defaults.set(data, forKey: key)
    }
}
