import Foundation
import Combine

enum MeetingPhase: Equatable {
    case idle, recording, transcribing, summarizing
    case ready(UUID), failed(String)
}

@MainActor
final class MeetingController: ObservableObject {
    @Published private(set) var phase: MeetingPhase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var records: [MeetingRecord] = []

    private let capture: MeetingCaptureService
    private let pipeline: MeetingTranscriptionPipeline
    private let summarizer: MeetingSummarizer
    private let store: MeetingStore
    private let deleteAudioAfterProcessing: Bool
    private var timer: Timer?
    private var workDir: URL?

    init(capture: MeetingCaptureService, pipeline: MeetingTranscriptionPipeline,
         summarizer: MeetingSummarizer, store: MeetingStore,
         deleteAudioAfterProcessing: Bool = true) {
        self.capture = capture; self.pipeline = pipeline
        self.summarizer = summarizer; self.store = store
        self.deleteAudioAfterProcessing = deleteAudioAfterProcessing
        self.records = (try? store.load()) ?? []
    }

    func start() {
        guard phase == .idle else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-\(UUID().uuidString)")
        workDir = dir
        do {
            try capture.start(workDir: dir)
            phase = .recording; elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed += 1 }
            }
        } catch {
            phase = .failed("Couldn't start capture: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard phase == .recording else { return }
        timer?.invalidate(); timer = nil
        let recording = capture.stop()
        phase = .transcribing
        Task { await process(recording) }
    }

    private func process(_ recording: MeetingRecording) async {
        do {
            let transcript = try await pipeline.run(recording)
            var record = MeetingRecord(
                id: UUID(), title: Self.defaultTitle(),
                date: recording.startedAt, duration: recording.duration,
                transcript: transcript, minutes: nil, speakerNames: [:])
            try store.save(record); reload()
            phase = .summarizing
            do {
                let minutes = try await summarizer.summarize(transcript, speakerNames: record.speakerNames)
                record.minutes = minutes
                try store.save(record); reload()
            } catch {
                // Transcript kept; summary failure is non-fatal.
            }
            if deleteAudioAfterProcessing { store.deleteAudio(recording) }
            phase = .ready(record.id)
        } catch {
            phase = .failed("Processing failed: \(error.localizedDescription)")
        }
    }

    func rename(id: UUID, remoteId: String, to name: String) {
        guard var rec = records.first(where: { $0.id == id }) else { return }
        rec.speakerNames[remoteId] = name
        try? store.save(rec); reload()
    }

    func delete(id: UUID) { try? store.delete(id: id); reload() }

    func rerunSummary(id: UUID) {
        guard var rec = records.first(where: { $0.id == id }) else { return }
        phase = .summarizing
        Task {
            if let m = try? await summarizer.summarize(rec.transcript, speakerNames: rec.speakerNames) {
                rec.minutes = m; try? store.save(rec); reload()
            }
            phase = .ready(id)
        }
    }

    private func reload() { records = (try? store.load()) ?? [] }
    private static func defaultTitle() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return "Meeting \(f.string(from: Date()))"
    }
}
