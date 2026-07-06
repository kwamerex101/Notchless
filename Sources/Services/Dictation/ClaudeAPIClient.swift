import Foundation

/// Direct Anthropic Messages API client for transcript cleanup. Used when the
/// cleanup backend is set to "Anthropic API" (or "Automatic" with a key set).
/// Returns nil on any failure so callers can fall back to the raw transcript.
enum ClaudeAPIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-haiku-4-5-20251001"

    static func clean(_ text: String, apiKey: String, systemPrompt: String, timeout: TimeInterval) async -> String? {
        guard !apiKey.isEmpty else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": text]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = data

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let first = content.first,
                  let out = first["text"] as? String else { return nil }
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }
}
