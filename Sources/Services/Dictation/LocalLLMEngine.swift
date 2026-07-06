import Foundation
#if canImport(LLM)
import LLM
#endif

/// On-device transcript cleanup via a local Gemma GGUF model (llama.cpp, through
/// the LLM.swift wrapper). The model file is managed by `LLMModelStore`; this
/// actor loads it once and reuses it. Returns nil whenever the model isn't
/// available so callers fall back to the raw transcript.
actor LocalLLMEngine {
    static let shared = LocalLLMEngine()

    #if canImport(LLM)
    private var bot: LLM?
    private var loadedPath: String?

    /// A stable system prompt; the per-call instruction rides in the input so we
    /// never reload the model just because intensity/context changed.
    private static let systemPrompt =
        "You are a careful text-cleanup tool. Follow the user's instruction exactly and output only the cleaned text, with no preamble."
    #endif

    func clean(_ text: String, systemPrompt instruction: String, timeout: TimeInterval) async -> String? {
        #if canImport(LLM)
        guard let path = await MainActor.run(body: { LLMModelStore.shared.readyFileURL()?.path }) else {
            return nil
        }
        if bot == nil || loadedPath != path {
            bot = LLM(from: URL(fileURLWithPath: path), template: .chatML(Self.systemPrompt))
            loadedPath = path
        }
        guard let bot else { return nil }

        let input = "\(instruction)\n\nText:\n\(text)"

        // Race generation against the timeout; stop() unblocks a slow decode.
        let generate = Task { await bot.respond(to: input) }
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            bot.stop()
        }
        await generate.value
        timeoutTask.cancel()

        let output = await MainActor.run { bot.output }.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
        #else
        return nil
        #endif
    }
}
