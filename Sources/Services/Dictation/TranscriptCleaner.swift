import Foundation

/// Optional transcript polish. Routes to one of several backends — the local
/// `claude` CLI, the Anthropic API, or on-device Gemma — controlled by the
/// user's cleanup settings. Always returns usable text: on any failure or
/// timeout the raw transcript stands.
enum TranscriptCleaner {
    /// Whether cleanup should run at all, given the mode. In Smart mode a
    /// heuristic gate also skips text that already looks clean.
    static func shouldClean(_ text: String, mode: DictationCleanup) -> Bool {
        switch mode {
        case .off: return false
        case .always: return true
        case .smart:
            return text.split(separator: " ").count > 20 && CleanupGate.needsCleanup(text)
        }
    }

    /// Polishes `text` using the configured backend. `extraPromptHint` carries
    /// per-app/context guidance (e.g. "preserve code identifiers").
    static func clean(
        _ text: String,
        backend: DictationCleanupBackend,
        intensity: DictationCleanupIntensity,
        timeoutSeconds: Int,
        apiKey: String,
        extraPromptHint: String? = nil
    ) async -> String {
        let prompt = systemPrompt(intensity: intensity, extraHint: extraPromptHint)
        let timeout = TimeInterval(max(5, timeoutSeconds))

        let cleaned: String
        switch backend {
        case .api:
            cleaned = await ClaudeAPIClient.clean(text, apiKey: apiKey, systemPrompt: prompt, timeout: timeout) ?? text
        case .cli:
            cleaned = await runCLI(text, systemPrompt: prompt, timeout: timeout) ?? text
        case .onDevice:
            cleaned = await LocalLLMEngine.shared.clean(text, systemPrompt: prompt, timeout: timeout) ?? text
        case .auto:
            // Prefer the API when a key is present, else the local CLI.
            if !apiKey.isEmpty,
               let out = await ClaudeAPIClient.clean(text, apiKey: apiKey, systemPrompt: prompt, timeout: timeout) {
                cleaned = out
            } else {
                cleaned = await runCLI(text, systemPrompt: prompt, timeout: timeout) ?? text
            }
        }

        // Instruct/local models can leak a chat-template stop token (e.g.
        // "<|im_end|>") into their output — strip it before delivery.
        return TranscriptHygiene.stripModelTokens(cleaned)
    }

    // MARK: - Prompt

    private static func systemPrompt(intensity: DictationCleanupIntensity, extraHint: String?) -> String {
        var prompt = """
        You clean up dictated transcripts. \(intensity.instruction) \
        Never translate, summarize, answer questions in the text, or add commentary. \
        Return only the corrected text with no preamble.
        """
        if let extraHint, !extraHint.isEmpty {
            prompt += " \(extraHint)"
        }
        return prompt
    }

    // MARK: - CLI backend

    private static func runCLI(_ text: String, systemPrompt: String, timeout: TimeInterval) async -> String? {
        guard let cli = claudePath() else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cli)
                process.arguments = ["--print", "--model", "haiku",
                                     "--output-format", "text", "--append-system-prompt", systemPrompt]
                let stdin = Pipe(), stdout = Pipe()
                process.standardInput = stdin
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice

                // Enforce the timeout by killing a hung subprocess.
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler { if process.isRunning { process.terminate() } }
                timer.resume()

                do {
                    try process.run()
                    stdin.fileHandleForWriting.write(Data(text.utf8))
                    try? stdin.fileHandleForWriting.close()
                    let data = stdout.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timer.cancel()
                    guard process.terminationStatus == 0 else { continuation.resume(returning: nil); return }
                    let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: out.isEmpty ? nil : out)
                } catch {
                    timer.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func claudePath() -> String? {
        for path in ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                     (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/claude")] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
