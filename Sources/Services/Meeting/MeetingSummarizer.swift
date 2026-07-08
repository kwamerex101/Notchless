import Foundation

protocol MinutesAPIClient {
    /// Returns the model's raw text response (expected to be JSON matching the schema).
    func minutesJSON(prompt: String, model: String) async throws -> String
}

struct MeetingSummarizer {
    let client: MinutesAPIClient
    let model: String

    init(client: MinutesAPIClient, model: String = "claude-sonnet-5") {
        self.client = client
        self.model = model
    }

    static func transcriptText(_ t: MeetingTranscript, speakerNames: [String: String]) -> String {
        t.segments
            .map { "\($0.speaker.displayName(speakerNames)): \($0.text)" }
            .joined(separator: "\n")
    }

    func summarize(_ transcript: MeetingTranscript,
                   speakerNames: [String: String]) async throws -> MeetingMinutes {
        let body = Self.transcriptText(transcript, speakerNames: speakerNames)
        let prompt = """
        You are summarizing a meeting transcript. Return ONLY JSON with this exact shape:
        {"summary": string, "decisions": [string], "actionItems": [{"text": string, "owner": "you" | "<speaker label>" | null}]}
        Attribute action items to the speaker who owns them when clear; otherwise null.

        Transcript:
        \(body)
        """
        let raw = try await client.minutesJSON(prompt: prompt, model: model)
        return try Self.parse(raw)
    }

    static func parse(_ raw: String) throws -> MeetingMinutes {
        // Tolerate code-fenced JSON.
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        struct Wire: Decodable {
            struct AI: Decodable { let text: String; let owner: String? }
            let summary: String; let decisions: [String]; let actionItems: [AI]
        }
        let w = try JSONDecoder().decode(Wire.self, from: Data(cleaned.utf8))
        let items = w.actionItems.map { ai -> ActionItem in
            let owner: Speaker? = ai.owner.flatMap { o in
                o.lowercased() == "you" ? .you : nil   // remote-name resolution is best-effort v1
            }
            return ActionItem(text: ai.text, owner: owner)
        }
        return MeetingMinutes(summary: w.summary, decisions: w.decisions, actionItems: items)
    }
}

/// Real Anthropic Messages API adapter for `MeetingSummarizer`. Non-streaming — minutes
/// output is small, so a plain messages call keeps the JSON response clean (no
/// streaming/thinking/effort params, unlike the dictation cleanup path).
struct AnthropicMinutesAPIClient: MinutesAPIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum ClientError: Error {
        case missingAPIKey
        case httpError(Int)
        case malformedResponse
    }

    /// Read at request time (not construction) so a key entered after launch
    /// takes effect without relaunching.
    var keyProvider: () -> String

    func minutesJSON(prompt: String, model: String) async throws -> String {
        let apiKey = keyProvider()
        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.httpError(code)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ClientError.malformedResponse
        }
        return text
    }
}
