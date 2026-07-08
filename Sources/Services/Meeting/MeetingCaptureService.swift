import AVFoundation
import Foundation

/// Appends mono Float PCM to a WAV file at a fixed sample rate. `append` runs on
/// the audio thread; it allocates one `AVAudioPCMBuffer` per call (acceptable here —
/// buffer sizes are stable). `close` flushes.
final class WAVWriter {
    private var file: AVAudioFile?
    private let format: AVAudioFormat

    init(url: URL, sampleRate: Double) throws {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                               channels: 1, interleaved: false)!
        file = try AVAudioFile(forWriting: url,
                               settings: format.settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func append(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0, let file,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
        else { return }
        buf.frameLength = AVAudioFrameCount(count)
        memcpy(buf.floatChannelData![0], samples, count * MemoryLayout<Float>.size)
        try? file.write(from: buf)
    }

    // AVAudioFile only finalizes the WAV header (frame count) once its last
    // strong reference is released — dropping it here forces that deinit so
    // the file is immediately readable, rather than waiting on WAVWriter's own
    // deinit (which may be delayed by other retaining closures).
    func close() { file = nil }
}

/// Downmixes the interleaved system-tap buffer to mono and writes it. Plain class
/// (NOT @MainActor) so the IO-thread callback can mutate it without crossing actor
/// isolation. Opens its WAVWriter lazily on the first callback, once the real sample
/// rate is known.
final class RemoteStreamRecorder {
    private let url: URL
    private var writer: WAVWriter?
    private var mono: [Float] = []
    init(url: URL) { self.url = url }

    func append(_ ptr: UnsafePointer<Float>, frameCount: Int, channels: Int, sampleRate: Double) {
        guard frameCount > 0 else { return }
        if writer == nil { writer = try? WAVWriter(url: url, sampleRate: sampleRate) }
        guard let writer else { return }
        if channels <= 1 {
            writer.append(ptr, count: frameCount)
        } else {
            if mono.count < frameCount { mono = [Float](repeating: 0, count: frameCount) }
            for i in 0..<frameCount {
                var s: Float = 0
                for c in 0..<channels { s += ptr[i * channels + c] }
                mono[i] = s / Float(channels)
            }
            mono.withUnsafeBufferPointer { writer.append($0.baseAddress!, count: frameCount) }
        }
    }

    func close() { writer?.close() }
}

@MainActor
final class MeetingCaptureService {
    private let systemTap: SystemAudioTap
    private let engine = AVAudioEngine()
    private var micWriter: WAVWriter?
    private var remoteRecorder: RemoteStreamRecorder?
    private var startDate: Date?
    private var micURL: URL?
    private var remoteURL: URL?

    private(set) var isRecording = false

    init(systemTap: SystemAudioTap) { self.systemTap = systemTap }

    func start(workDir: URL) throws {
        guard !isRecording else { return }
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let mic = workDir.appendingPathComponent("mic.wav")
        let remote = workDir.appendingPathComponent("remote.wav")
        micURL = mic; remoteURL = remote

        // Remote: interleaved PCM from the existing system tap → mono WAV at the tap's rate.
        let recorder = RemoteStreamRecorder(url: remote)
        remoteRecorder = recorder
        systemTap.onPCM = { [weak recorder] ptr, frames, channels, rate in
            recorder?.append(ptr, frameCount: frames, channels: channels, sampleRate: rate)
        }

        // Mic: AVAudioEngine input tap. Write channel 0 (mono) at the input's native rate;
        // the pipeline (Task 6) resamples to 16 kHz for ASR.
        let input = engine.inputNode
        let inFormat = input.inputFormat(forBus: 0)
        let mWriter = try WAVWriter(url: mic, sampleRate: inFormat.sampleRate)
        micWriter = mWriter
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak mWriter] buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            mWriter?.append(ch, count: Int(buffer.frameLength))
        }
        try engine.start()

        startDate = Date()
        isRecording = true
    }

    func stop() -> MeetingRecording {
        systemTap.onPCM = nil                      // detach the sink BEFORE closing the recorder
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        micWriter?.close(); remoteRecorder?.close()
        let start = startDate ?? Date()
        let recording = MeetingRecording(
            micURL: micURL!, remoteURL: remoteURL!,
            startedAt: start, duration: Date().timeIntervalSince(start))
        micWriter = nil; remoteRecorder = nil; isRecording = false
        return recording
    }
}
