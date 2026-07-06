import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

/// Dictation backend that captures microphone audio, resamples it to 16 kHz
/// mono, and transcribes the whole utterance with Parakeet TDT on the Neural
/// Engine (via `ParakeetModelStore`). Unlike Apple Speech this is an offline,
/// finish-then-transcribe engine: samples are accumulated while the hotkey is
/// held and decoded once on release.
@MainActor
final class ParakeetTranscriber: DictationTranscriber {
    var onPartial: ((String) -> Void)?
    var onLevel: ((CGFloat) -> Void)?
    var onSpectrum: (([CGFloat]) -> Void)?

    private let engine = AVAudioEngine()
    private var sink: AudioSink?
    private var microphoneUID = ""

    /// Applied on the next `start()`.
    func configure(microphoneUID: String) {
        self.microphoneUID = microphoneUID
    }

    func start() async throws {
        guard await Self.requestMic() else { throw DictationError.microphoneDenied }
        // Surface an early, honest error on Intel Macs rather than failing at finish.
        #if !arch(arm64)
        throw ParakeetError.unsupportedHardware
        #endif

        // Warm the model up now so release-to-transcribe is snappy.
        ParakeetModelStore.shared.preload()

        applyPreferredInputDevice()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Owns the converter + accumulated samples off the main actor so the
        // realtime tap can touch them safely.
        let sink = AudioSink(inputFormat: format)
        self.sink = sink
        let analyzer = SpectrumAnalyzer()

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            sink.accept(buffer)
            let level = Self.level(from: buffer)
            let spectrum = buffer.floatChannelData.map { analyzer.bands(from: $0[0], count: Int(buffer.frameLength)) } ?? []
            DispatchQueue.main.async {
                self?.onLevel?(level)
                self?.onSpectrum?(spectrum)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func finish() async -> String {
        stopCapture()
        let captured = sink?.drain() ?? []
        sink = nil
        guard !captured.isEmpty else { return "" }
        do {
            return try await ParakeetModelStore.shared.transcribe(captured)
        } catch {
            return ""
        }
    }

    func cancel() {
        stopCapture()
        sink = nil
    }

    // MARK: - Capture helpers

    private func stopCapture() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    /// Points AVAudioEngine's input at the user's chosen device (best-effort).
    private func applyPreferredInputDevice() {
        guard !microphoneUID.isEmpty,
              var deviceID = Self.deviceID(forUID: microphoneUID),
              let unit = engine.inputNode.audioUnit else { return }
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var cfUID = uid as CFString
        var translation = AudioValueTranslation(
            mInputData: &cfUID, mInputDataSize: UInt32(MemoryLayout<CFString>.size),
            mOutputData: &deviceID, mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &translation)
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    private static func level(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = (sum / Float(count)).squareRoot()
        return CGFloat(min(1, max(0, rms * 12)))
    }

    private static func requestMic() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}

/// Resamples realtime input buffers to 16 kHz mono and accumulates the floats.
/// Lives off the main actor so the realtime audio tap can call `accept` safely;
/// all state is guarded by a lock.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Float] = []
    private let converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    init(inputFormat: AVAudioFormat) {
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
    }

    func accept(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard let channel = out.floatChannelData, out.frameLength > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        storage.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
    }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let copy = storage
        storage.removeAll(keepingCapacity: false)
        return copy
    }
}
