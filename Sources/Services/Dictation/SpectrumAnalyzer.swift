import Foundation
import Accelerate

/// Turns a chunk of mono audio samples into a handful of normalized frequency
/// band levels (low → high) for the recording waveform. Uses a windowed FFT and
/// an auto-decaying peak so it adapts to any input loudness without a magic gain.
///
/// Created per capture session and only ever called from the realtime audio
/// thread, so its small mutable state needs no locking.
final class SpectrumAnalyzer: @unchecked Sendable {
    private let bandCount: Int
    private let fftSize = 1024
    private let halfSize = 512
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var runningPeak: Float = 1e-4
    /// Per-band smoothed output: fast rise, slow fall, so bars snap up on a beat
    /// and ease down instead of jittering frame-to-frame.
    private var smoothed: [CGFloat]
    private let attack: CGFloat = 0.6
    private let release: CGFloat = 0.22

    init(bandCount: Int = 6) {
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        self.window = [Float](repeating: 0, count: fftSize)
        self.smoothed = [CGFloat](repeating: 0, count: bandCount)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func bands(from samples: UnsafePointer<Float>, count: Int) -> [CGFloat] {
        let n = min(count, fftSize)
        guard n > 0 else { return [CGFloat](repeating: 0, count: bandCount) }

        // Window the input (remaining samples stay zero-padded).
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(n))

        var real = [Float](repeating: 0, count: halfSize)
        var imag = [Float](repeating: 0, count: halfSize)
        var magnitudes = [Float](repeating: 0, count: halfSize)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { inPtr in
                    inPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        // Group bins into log-spaced bands (skip DC), taking each band's peak.
        var rawBands = [Float](repeating: 0, count: bandCount)
        for b in 0..<bandCount {
            let lo = binIndex(b)
            let hi = max(lo + 1, binIndex(b + 1))
            var peak: Float = 0
            for k in lo..<min(hi, halfSize) { peak = max(peak, magnitudes[k]) }
            rawBands[b] = sqrt(peak)   // magnitudes are squared power
        }

        // Auto-normalize against a slowly-decaying peak so quiet and loud speech
        // both fill the bars sensibly.
        let frameMax = rawBands.max() ?? 0
        runningPeak = max(runningPeak * 0.995, frameMax, 1e-4)

        // Fast-attack / slow-release smoothing: bars pop up on transients and
        // ease back down instead of flickering each frame.
        for b in 0..<bandCount {
            let target = CGFloat(min(1, rawBands[b] / runningPeak))
            let coeff = target > smoothed[b] ? attack : release
            smoothed[b] += (target - smoothed[b]) * coeff
        }
        return smoothed
    }

    /// Log-spaced bin boundary for band `b`, biased toward the speech range.
    private func binIndex(_ b: Int) -> Int {
        let fraction = Double(b) / Double(bandCount)
        let minBin = 1.0
        let maxBin = Double(halfSize)
        let value = minBin * pow(maxBin / minBin, fraction)
        return max(1, min(halfSize, Int(value)))
    }
}
