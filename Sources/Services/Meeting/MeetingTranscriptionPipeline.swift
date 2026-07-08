import Foundation
import FluidAudio

/// Diarize+transcribe the remote stream and VAD+transcribe the mic stream,
/// then merge by timestamp. Runs off the main actor (Parakeet transcription
/// itself hops to `@MainActor` internally via `ParakeetModelStore`).
///
/// FluidAudio 0.15.2 API confirmed by reading the checked-out package source
/// (`SourcePackages/checkouts/FluidAudio`): `OfflineDiarizerManager` for
/// remote-stream diarization, the Silero-based `VadManager` for mic-stream
/// speech segmentation, and `AudioConverter.resampleAudioFile` for 16 kHz
/// mono resampling.
@available(macOS 14.0, *)
struct MeetingTranscriptionPipeline {
    func run(_ recording: MeetingRecording) async throws -> MeetingTranscript {
        // The mic ("You") transcript is the user's own audio — it must survive
        // even when the far side produced no capturable audio (no remote.wav,
        // silent call, decode failure). So transcribe "You" normally, but let a
        // remote failure degrade to an empty remote track instead of throwing
        // away the whole run.
        let youSegs = try await transcribeYou(recording.micURL)
        let remoteSegs = (try? await transcribeRemote(recording.remoteURL)) ?? []
        return TranscriptMerger.merge(you: youSegs, remote: remoteSegs, duration: recording.duration)
    }

    // MARK: mic → "You" utterances

    private func transcribeYou(_ url: URL) async throws -> [TranscriptSegment] {
        // Resample the whole mic file ONCE, then reuse the in-memory buffer for
        // both VAD segmentation and every slice — no per-segment re-decode.
        let samples = try AudioConverter().resampleAudioFile(url)
        let ranges = try await voiceRanges(samples)
        var out: [TranscriptSegment] = []
        for r in ranges {
            let text = try await transcribeSlice(samples: samples, start: r.start, end: r.end)
            out.append(TranscriptSegment(speaker: .you, start: r.start, end: r.end,
                                         text: text, qualityScore: nil))
        }
        return out
    }

    // MARK: remote → per-speaker segments

    private func transcribeRemote(_ url: URL) async throws -> [TranscriptSegment] {
        let diarizer = OfflineDiarizerManager(config: OfflineDiarizerConfig())
        try await diarizer.prepareModels()
        let result = try await diarizer.process(url)
        // Resample the whole remote file ONCE and slice each segment from it.
        let samples = try AudioConverter().resampleAudioFile(url)
        var out: [TranscriptSegment] = []
        for seg in result.segments {
            let start = TimeInterval(seg.startTimeSeconds)
            let end = TimeInterval(seg.endTimeSeconds)
            let text = try await transcribeSlice(samples: samples, start: start, end: end)
            out.append(TranscriptSegment(
                speaker: .remote(id: seg.speakerId, name: nil),
                start: start, end: end,
                text: text, qualityScore: Double(seg.qualityScore)))
        }
        return out
    }

    // MARK: helpers

    /// VAD utterance ranges for the mic (single-speaker) stream, via FluidAudio's
    /// `VadManager.segmentSpeech`. Takes the already-resampled 16 kHz mono buffer
    /// so the mic file isn't decoded twice. Falls back to one whole-file range if
    /// VAD finds no speech (e.g. a very short/quiet clip) so the "You" track is
    /// never silently dropped.
    private func voiceRanges(_ samples: [Float]) async throws -> [(start: TimeInterval, end: TimeInterval)] {
        guard !samples.isEmpty else { return [] }

        let vad = try await VadManager()
        let segments = try await vad.segmentSpeech(samples)
        if segments.isEmpty {
            let whole = TimeInterval(samples.count) / TimeInterval(VadManager.sampleRate)
            return [(start: 0, end: whole)]
        }
        return segments.map { (start: $0.startTime, end: $0.endTime) }
    }

    /// Slice a [start,end] window (seconds) out of an already-resampled 16 kHz
    /// mono buffer and run Parakeet on it.
    private func transcribeSlice(samples: [Float],
                                 start: TimeInterval,
                                 end: TimeInterval) async throws -> String {
        let sampleRate = TimeInterval(VadManager.sampleRate)
        let lo = max(0, Int(start * sampleRate))
        let hi = min(samples.count, Int(end * sampleRate))
        guard hi > lo else { return "" }
        let slice = samples[lo..<hi]
        return try await ParakeetModelStore.shared.transcribe(Array(slice))
    }
}
