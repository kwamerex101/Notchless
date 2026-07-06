import Foundation

/// On-device transcript cleanup via a local Gemma GGUF model (llama.cpp).
/// Placeholder seam: the native llama.cpp integration is wired in a later step.
/// Until a model is loaded, `clean` returns nil so callers fall back to the raw
/// transcript (or another backend).
actor LocalLLMEngine {
    static let shared = LocalLLMEngine()

    func clean(_ text: String, systemPrompt: String, timeout: TimeInterval) async -> String? {
        // Not yet available — see ParakeetEngine for the model-download pattern
        // the Gemma path will follow.
        return nil
    }
}
