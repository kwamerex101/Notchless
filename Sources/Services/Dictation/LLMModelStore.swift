import Foundation
import Combine

/// A downloadable on-device cleanup model (Gemma GGUF), mirroring ListenToMe's
/// E2B/12B choice with smaller, faster defaults suited to punctuation cleanup.
enum LocalLLMModel: String, CaseIterable, Identifiable {
    case gemma1B
    case gemma4B

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gemma1B: return "Gemma 3 · 1B (fast)"
        case .gemma4B: return "Gemma 3 · 4B (better)"
        }
    }

    var sizeText: String {
        switch self {
        case .gemma1B: return "~0.8 GB"
        case .gemma4B: return "~2.5 GB"
        }
    }

    var fileName: String {
        switch self {
        case .gemma1B: return "gemma-3-1b-it-Q4_K_M.gguf"
        case .gemma4B: return "gemma-3-4b-it-Q4_K_M.gguf"
        }
    }

    /// Official ggml-org GGUF conversions on Hugging Face.
    var remoteURL: URL {
        switch self {
        case .gemma1B:
            return URL(string: "https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf")!
        case .gemma4B:
            return URL(string: "https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF/resolve/main/gemma-3-4b-it-Q4_K_M.gguf")!
        }
    }
}

/// Downloads and tracks the on-device cleanup model file. Loading + inference
/// live in `LocalLLMEngine`; this store owns the bytes on disk and the UI state.
@MainActor
final class LLMModelStore: NSObject, ObservableObject {
    static let shared = LLMModelStore()

    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status = .notDownloaded

    /// The model the user has selected to use.
    var selected: LocalLLMModel {
        get { LocalLLMModel(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .gemma1B }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            refreshStatus()
            objectWillChange.send()
        }
    }
    private let key = "dictation.localLLMModel"

    private var downloadTask: URLSessionDownloadTask?

    nonisolated static var modelsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchless/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// On-disk location for a model (whether present or not).
    func fileURL(for model: LocalLLMModel) -> URL {
        Self.modelsDirectory.appendingPathComponent(model.fileName)
    }

    /// The selected model's file if it's fully downloaded.
    func readyFileURL() -> URL? {
        let url = fileURL(for: selected)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    override init() {
        super.init()
        refreshStatus()
    }

    func refreshStatus() {
        if case .downloading = status { return }
        status = FileManager.default.fileExists(atPath: fileURL(for: selected).path) ? .ready : .notDownloaded
    }

    func download() {
        guard downloadTask == nil else { return }
        status = .downloading(0)
        DictationLog.log("gemma: starting download \(selected.fileName)")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: selected.remoteURL)
        downloadTask = task
        task.resume()
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL(for: selected))
        refreshStatus()
    }
}

extension LLMModelStore: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            if case .downloading = self.status { self.status = .downloading(fraction) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // Move synchronously here — `location` is deleted when this returns.
        let model = DispatchQueue.main.sync { self.selected }
        let destination = Self.modelsDirectory.appendingPathComponent(model.fileName)
        try? FileManager.default.removeItem(at: destination)
        let moved = (try? FileManager.default.moveItem(at: location, to: destination)) != nil
        Task { @MainActor in
            self.downloadTask = nil
            if moved {
                DictationLog.log("gemma: download complete")
                self.status = .ready
            } else {
                self.status = .failed("Couldn't save model")
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in
            self.downloadTask = nil
            DictationLog.log("gemma: download FAILED: \(error.localizedDescription)")
            self.status = .failed(error.localizedDescription)
        }
    }
}
