import Foundation
import Combine
import OSLog

enum MeetingPhase: Equatable {
    case idle, recording, transcribing, summarizing
    case ready(UUID), failed(String)
}

@MainActor
final class MeetingController: ObservableObject {
    @Published private(set) var phase: MeetingPhase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var records: [MeetingRecord] = []

    /// True while actively recording — used by AppDelegate to keep the system-audio
    /// tap running during a meeting (it otherwise only runs for the now-playing visualizer).
    var isCapturing: Bool { phase == .recording }
    /// Human-readable reason the last AI summary failed (nil when none). Surfaced
    /// in the notch/Settings so "summary failed" is actionable.
    @Published private(set) var summaryError: String?

    private static let log = Logger(subsystem: "com.rexdanquah.Notchless", category: "Meeting")

    private let capture: MeetingCaptureService
    private let pipeline: MeetingTranscriptionPipeline
    private let summarizer: MeetingSummarizer
    /// Rebuilds the summarizer per request so a key entered / model picked after
    /// launch takes effect without relaunching. Nil in tests, which inject a
    /// fixed `summarizer` directly.
    private let makeSummarizer: (() -> MeetingSummarizer)?
    private let store: MeetingStore
    private let deleteAudioAfterProcessing: Bool
    private var timer: Timer?

    init(capture: MeetingCaptureService, pipeline: MeetingTranscriptionPipeline,
         summarizer: MeetingSummarizer, store: MeetingStore,
         makeSummarizer: (() -> MeetingSummarizer)? = nil,
         deleteAudioAfterProcessing: Bool = true) {
        self.capture = capture; self.pipeline = pipeline
        self.summarizer = summarizer; self.store = store
        self.makeSummarizer = makeSummarizer
        self.deleteAudioAfterProcessing = deleteAudioAfterProcessing
        self.records = (try? store.load()) ?? []
    }

    func start() {
        guard phase == .idle else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-\(UUID().uuidString)")
        do {
            try capture.start(workDir: dir)
            phase = .recording; elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.elapsed += 1 }
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
            let summarizer = makeSummarizer?() ?? self.summarizer
            do {
                let minutes = try await summarizer.summarize(transcript, speakerNames: record.speakerNames)
                record.minutes = minutes
                summaryError = nil
                try store.save(record); reload()
            } catch {
                // Transcript kept; summary failure is non-fatal — flag it, log the
                // real cause, and surface it so the UI's retry is actionable.
                record.summaryFailed = true
                summaryError = error.localizedDescription
                Self.log.error("meeting summary failed: \(error.localizedDescription, privacy: .public)")
                try? store.save(record); reload()
            }
            // Live read (defaults true when unset) so the Settings toggle takes
            // effect without relaunching.
            let deleteAudio = UserDefaults.standard.object(forKey: "meeting.deleteAudio") as? Bool ?? true
            if deleteAudio { store.deleteAudio(recording) }
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

    /// Return to idle after a completed/failed meeting so a new one can be recorded.
    func reset() {
        if case .ready = phase { phase = .idle; elapsed = 0; summaryError = nil; return }
        if case .failed = phase { phase = .idle; elapsed = 0; summaryError = nil; return }
    }

    func rerunSummary(id: UUID) {
        switch phase {
        case .idle, .ready, .failed: break
        case .recording, .transcribing, .summarizing: return
        }
        guard var rec = records.first(where: { $0.id == id }) else { return }
        phase = .summarizing
        let summarizer = makeSummarizer?() ?? self.summarizer
        Task {
            do {
                let m = try await summarizer.summarize(rec.transcript, speakerNames: rec.speakerNames)
                rec.minutes = m; rec.summaryFailed = false
                summaryError = nil
                try? store.save(rec); reload()
            } catch {
                rec.summaryFailed = true
                summaryError = error.localizedDescription
                Self.log.error("meeting summary retry failed: \(error.localizedDescription, privacy: .public)")
                try? store.save(rec); reload()
            }
            phase = .ready(id)
        }
    }

    /// Debug-harness only: drives `phase`/`elapsed` directly, without touching
    /// `capture` — so `DebugStateDump` can render the `.recording` states
    /// (red pulsing dot, elapsed readout) without starting a real system-audio
    /// tap. Not gated behind `#if DEBUG` because the dump harness runs in
    /// release builds too; the seam is a plain no-op unless a caller invokes it.
    func debugSetRecording(elapsed: TimeInterval) {
        phase = .recording
        self.elapsed = elapsed
    }

    private func reload() { records = (try? store.load()) ?? [] }
    private static func defaultTitle() -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return "Meeting \(f.string(from: Date()))"
    }
}
