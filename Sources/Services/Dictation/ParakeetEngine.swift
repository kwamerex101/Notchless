import Foundation
import FluidAudio

/// Owns the Parakeet TDT model (downloaded + loaded once) and runs offline
/// transcription on captured samples. The model is ~600 MB and runs on the
/// Neural Engine, so it's Apple-Silicon only and loaded lazily on first use.
///
/// UI observes `status`; audio capture lives in `ParakeetTranscriber`, which
/// hands finished 16 kHz mono samples here for a single `transcribe` call.
@MainActor
final class ParakeetModelStore: ObservableObject {
    static let shared = ParakeetModelStore()

    enum Status: Equatable {
        case notLoaded
        case downloading(Double)   // 0…1 fraction complete
        case ready
        case unsupported           // not Apple Silicon
        case failed(String)

        var isReady: Bool { self == .ready }
    }

    @Published private(set) var status: Status = .notLoaded

    private var manager: AsrManager?
    private var loadTask: Task<AsrManager, Error>?

    /// Downloads (first run) and loads the model, returning a ready manager.
    /// Concurrent callers share a single in-flight load.
    func ensureLoaded() async throws -> AsrManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.value }

        #if arch(arm64)
        DictationLog.log("parakeet: starting download+load (v3)")
        status = .downloading(0)
        let task = Task { () throws -> AsrManager in
            let models = try await AsrModels.downloadAndLoad(
                version: .v3,
                progressHandler: { progress in
                    Task { @MainActor [weak self] in
                        // Don't stomp on `.ready` if a late callback arrives.
                        if case .downloading = self?.status {
                            self?.status = .downloading(progress.fractionCompleted)
                        }
                    }
                }
            )
            return AsrManager(models: models)
        }
        loadTask = task
        do {
            let manager = try await task.value
            self.manager = manager
            self.loadTask = nil
            self.status = .ready
            DictationLog.log("parakeet: model ready")
            return manager
        } catch {
            self.loadTask = nil
            self.status = .failed(error.localizedDescription)
            DictationLog.log("parakeet: load FAILED: \(error)")
            throw error
        }
        #else
        status = .unsupported
        throw ParakeetError.unsupportedHardware
        #endif
    }

    /// Kicks off the download/load without blocking (used by the "Download"
    /// button in settings). Errors surface through `status`.
    func preload() {
        Task { try? await ensureLoaded() }
    }

    /// Transcribes 16 kHz mono float samples into text.
    func transcribe(_ samples: [Float]) async throws -> String {
        let manager = try await ensureLoaded()
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ParakeetError: LocalizedError {
    case unsupportedHardware
    case noAudio

    var errorDescription: String? {
        switch self {
        case .unsupportedHardware: return "Parakeet needs an Apple Silicon Mac"
        case .noAudio: return "Couldn't hear that"
        }
    }
}
