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
        async let you = transcribeYou(recording.micURL)
        async let them = transcribeRemote(recording.remoteURL)
        let (youSegs, remoteSegs) = try await (you, them)
        return TranscriptMerger.merge(you: youSegs, remote: remoteSegs, duration: recording.duration)
    }

    // MARK: mic → "You" utterances

    private func transcribeYou(_ url: URL) async throws -> [TranscriptSegment] {
        let ranges = try await voiceRanges(url)
        var out: [TranscriptSegment] = []
        for r in ranges {
            let text = try await transcribeSlice(url, start: r.start, end: r.end)
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
        var out: [TranscriptSegment] = []
        for seg in result.segments {
            let start = TimeInterval(seg.startTimeSeconds)
            let end = TimeInterval(seg.endTimeSeconds)
            let text = try await transcribeSlice(url, start: start, end: end)
            out.append(TranscriptSegment(
                speaker: .remote(id: seg.speakerId, name: nil),
                start: start, end: end,
                text: text, qualityScore: Double(seg.qualityScore)))
        }
        return out
    }

    // MARK: helpers

    /// VAD utterance ranges for the mic (single-speaker) stream, via FluidAudio's
    /// `VadManager.segmentSpeech`. Falls back to one whole-file range if VAD finds
    /// no speech (e.g. a very short/quiet clip) so the "You" track is never silently
    /// dropped.
    private func voiceRanges(_ url: URL) async throws -> [(start: TimeInterval, end: TimeInterval)] {
        let samples = try AudioConverter().resampleAudioFile(url)
        guard !samples.isEmpty else { return [] }

        let vad = try await VadManager()
        let segments = try await vad.segmentSpeech(samples)
        if segments.isEmpty {
            let whole = TimeInterval(samples.count) / TimeInterval(VadManager.sampleRate)
            return [(start: 0, end: whole)]
        }
        return segments.map { (start: $0.startTime, end: $0.endTime) }
    }

    /// Resample a [start,end] slice to 16 kHz mono Float and run Parakeet on it.
    private func transcribeSlice(_ url: URL,
                                 start: TimeInterval,
                                 end: TimeInterval) async throws -> String {
        let samples = try AudioConverter().resampleAudioFile(url)   // whole file, 16k mono Float
        let sampleRate = TimeInterval(VadManager.sampleRate)
        let lo = max(0, Int(start * sampleRate))
        let hi = min(samples.count, Int(end * sampleRate))
        guard hi > lo else { return "" }
        let slice = Array(samples[lo..<hi])
        return try await ParakeetModelStore.shared.transcribe(slice)
    }
}
