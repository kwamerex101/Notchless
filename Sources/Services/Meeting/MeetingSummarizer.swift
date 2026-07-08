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

    enum ClientError: LocalizedError {
        case missingAPIKey
        case httpError(Int, String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No Anthropic API key set — add one in Settings → Dictation."
            case let .httpError(code, body):
                let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
                return "Anthropic API error \(code)\(detail.isEmpty ? "" : ": \(detail.prefix(300))")"
            case .malformedResponse:
                return "Unexpected response from the Anthropic API."
            }
        }
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
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.httpError(code, bodyText)
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

/// Which backend generates the minutes.
enum MeetingSummaryBackend: String, CaseIterable, Identifiable {
    case subscription   // local `claude` CLI — uses your Claude Code / subscription sign-in, no API key
    case apiKey         // direct Anthropic API with a stored key

    var id: String { rawValue }
    var title: String {
        switch self {
        case .subscription: return "Claude subscription (claude CLI)"
        case .apiKey:       return "Anthropic API key"
        }
    }

    /// Live-read current selection (defaults to subscription).
    static var current: MeetingSummaryBackend {
        MeetingSummaryBackend(rawValue: UserDefaults.standard.string(forKey: "meeting.summarizerBackend") ?? "")
            ?? .subscription
    }
}

/// Generates minutes via the local `claude` CLI (Claude Code / subscription
/// sign-in) — no API key, billed to your Claude subscription. Mirrors the
/// dictation CLI-cleanup path (`TranscriptCleaner`).
struct ClaudeCLIMinutesClient: MinutesAPIClient {
    enum CLIError: LocalizedError {
        case notInstalled
        case failed(Int32, String)
        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "The `claude` CLI wasn't found. Install Claude Code and sign in, or switch to an Anthropic API key."
            case let .failed(code, err):
                let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
                return "claude CLI exited \(code)\(detail.isEmpty ? "" : ": \(detail.prefix(300))")"
            }
        }
    }

    var timeout: TimeInterval = 120

    func minutesJSON(prompt: String, model: String) async throws -> String {
        guard let cli = Self.claudePath() else { throw CLIError.notInstalled }
        let cliModel = Self.cliModel(model)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cli)
                process.arguments = ["--print", "--model", cliModel, "--output-format", "text",
                                     "--append-system-prompt",
                                     "Output only the raw JSON object requested. No prose, no code fences."]
                let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                process.standardInput = stdin
                process.standardOutput = stdout
                process.standardError = stderr

                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler { if process.isRunning { process.terminate() } }
                timer.resume()

                do {
                    try process.run()
                    stdin.fileHandleForWriting.write(Data(prompt.utf8))
                    try? stdin.fileHandleForWriting.close()
                    let out = stdout.fileHandleForReading.readDataToEndOfFile()
                    let err = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timer.cancel()
                    guard process.terminationStatus == 0 else {
                        continuation.resume(throwing: CLIError.failed(process.terminationStatus,
                                                                      String(decoding: err, as: UTF8.self)))
                        return
                    }
                    continuation.resume(returning: String(decoding: out, as: UTF8.self))
                } catch {
                    timer.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Whether the `claude` binary is present (used to show availability in Settings).
    static func isAvailable() -> Bool { claudePath() != nil }

    private static func claudePath() -> String? {
        for path in ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                     (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/claude")] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Map a full model id (or picker value) to a CLI model alias.
    private static func cliModel(_ m: String) -> String {
        let l = m.lowercased()
        if l.contains("opus") { return "opus" }
        if l.contains("haiku") { return "haiku" }
        return "sonnet"
    }
}
