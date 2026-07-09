import AVFoundation
import os

/// Low-latency click playback: every voice is pre-decoded into a PCM buffer
/// and scheduled on a small round-robin pool of player nodes, so rapid scroll
/// detents can overlap without cutting each other off. `play` is safe to call
/// from any thread (work hops to a serial queue); the engine starts lazily and
/// failure to start (headless CI, no output device) downgrades to silence.
private final class BundleToken {}

final class ClickSoundPlayer: ClickSounding {
    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var nextNode = 0
    private var engineReady = false
    private let queue = DispatchQueue(label: "com.rexdanquah.notchless.clicksound")

    private static let poolSize = 4

    /// Voice IDs whose buffers decoded successfully (diagnostics + tests).
    var loadedVoiceIDs: [String] {
        queue.sync { Array(buffers.keys) }
    }

    func preload() {
        queue.sync {
            guard buffers.isEmpty else { return }
            let bundle = Bundle(for: BundleToken.self)
            for voice in FeedbackVoice.all {
                guard let url = bundle.url(forResource: voice.assetName, withExtension: "wav"),
                      let file = try? AVAudioFile(forReading: url),
                      let buffer = AVAudioPCMBuffer(
                          pcmFormat: file.processingFormat,
                          frameCapacity: AVAudioFrameCount(file.length)),
                      (try? file.read(into: buffer)) != nil
                else {
                    Logger(subsystem: "Notchless", category: "ClickSound")
                        .error("failed to load voice \(voice.id, privacy: .public)")
                    continue
                }
                buffers[voice.id] = buffer
            }
        }
    }

    func play(_ voice: FeedbackVoice, volume: Double) {
        queue.async { [self] in
            guard let buffer = buffers[voice.id] else { return }
            guard ensureEngineRunning(format: buffer.format) else { return }
            let node = nodes[nextNode]
            nextNode = (nextNode + 1) % nodes.count
            node.volume = Float(max(0, min(1, volume)))
            node.scheduleBuffer(buffer, at: nil, options: .interrupts)
            node.play()
        }
    }

    // MARK: - Engine lifecycle (on `queue`)

    private func ensureEngineRunning(format: AVAudioFormat) -> Bool {
        if engineReady, engine.isRunning { return true }
        if nodes.isEmpty {
            for _ in 0..<Self.poolSize {
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
                nodes.append(node)
            }
        }
        do {
            try engine.start()
            engineReady = true
            return true
        } catch {
            // No output device (CI) or engine hiccup — stay silent, retry next play.
            engineReady = false
            return false
        }
    }
}
