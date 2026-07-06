import Foundation

/// A URL found in free text, with a tidy display domain.
struct DetectedLink: Equatable {
    let url: URL
    let domain: String
}

/// Finds URLs in note text via `NSDataDetector`. Pure and offline — it detects
/// and returns links; it never fetches them. Single source of truth for both
/// the notch's note/link glyph and the Settings domain chips.
enum LinkDetector {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// URLs in appearance order, de-duplicated by absolute string. `domain` is
    /// the host with a leading `www.` removed. URLs without a host are skipped.
    static func links(in text: String) -> [DetectedLink] {
        guard let detector, !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var result: [DetectedLink] = []
        detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let url = match?.url, let host = url.host else { return }
            let key = url.absoluteString
            guard seen.insert(key).inserted else { return }
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            result.append(DetectedLink(url: url, domain: domain))
        }
        return result
    }
}
