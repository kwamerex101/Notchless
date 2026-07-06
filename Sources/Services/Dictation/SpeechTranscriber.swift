import Foundation
import AVFoundation
import Speech

/// On-device dictation using Apple's Speech framework + AVAudioEngine mic
/// capture. Private by default: recognition runs on-device when supported.
@MainActor
final class SpeechTranscriber: DictationTranscriber {
    var onPartial: ((String) -> Void)?
    var onLevel: ((CGFloat) -> Void)?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finishContinuation: CheckedContinuation<String, Never>?

    func start() async throws {
        guard await Self.requestMic() else { throw DictationError.microphoneDenied }
        guard await Self.requestSpeech() else { throw DictationError.speechDenied }
        guard let recognizer, recognizer.isAvailable else { throw DictationError.recognizerUnavailable }

        latest = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        // The recognition handler is delivered on an arbitrary queue — hop to
        // the main actor before touching any state (never assumeIsolated here).
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.latest = result.bestTranscription.formattedString
                    self.onPartial?(self.latest)
                    if result.isFinal { self.completeFinish() }
                }
                if error != nil { self.completeFinish() }
            }
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Runs on the realtime audio thread; only touch the request here and
            // hand the level to the main actor.
            self?.request?.append(buffer)
            let level = Self.level(from: buffer)
            DispatchQueue.main.async { self?.onLevel?(level) }
        }

        engine.prepare()
        try engine.start()
    }

    func finish() async -> String {
        stopCapture()
        request?.endAudio()
        // Give the recognizer a moment to emit its final result.
        return await withCheckedContinuation { continuation in
            finishContinuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.completeFinish()
            }
        }
    }

    func cancel() {
        stopCapture()
        task?.cancel()
        request = nil
        task = nil
        finishContinuation?.resume(returning: "")
        finishContinuation = nil
    }

    // MARK: - Helpers

    private func completeFinish() {
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil
        stopCapture()
        task = nil
        request = nil
        continuation.resume(returning: latest.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func stopCapture() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    private static func level(from buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = (sum / Float(count)).squareRoot()
        // Map RMS to a lively 0…1 range.
        return CGFloat(min(1, max(0, rms * 12)))
    }

    private static func requestMic() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    private static func requestSpeech() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
