import AppKit
import Combine

/// Owns the active now-playing provider, pushes updates into the notch model,
/// and interpolates elapsed time between provider updates so the scrubber moves
/// smoothly while playing.
@MainActor
final class MediaController {
    private let model: NotchViewModel
    private let provider: NowPlayingProvider
    private var ticker: Timer?

    /// Elapsed time and the wall-clock instant it was last reported, so the
    /// ticker can extrapolate without drifting.
    private var baseElapsed: TimeInterval = 0
    private var baseInstant = Date()
    private var lastColorTitle: String?

    init(model: NotchViewModel, provider: NowPlayingProvider? = nil) {
        self.model = model
        // Prefer the bundled adapter (works on macOS 15.4+); fall back to the
        // direct MediaRemote binding on older systems where it still works.
        self.provider = provider
            ?? (AdapterNowPlayingProvider.isBundled ? AdapterNowPlayingProvider() : MediaRemoteProvider())
    }

    func start() {
        provider.onChange = { [weak self] info in
            guard let self else { return }
            self.baseElapsed = info?.elapsed ?? 0
            self.baseInstant = Date()
            // Re-extract the glow color only when the track changes, not on
            // every playback update.
            if info?.title != self.lastColorTitle {
                self.lastColorTitle = info?.title
                self.model.artworkColor = info?.artwork.flatMap(ColorExtractor.vibrantColor)
            }
            self.model.nowPlaying = info
            self.updateTicker(playing: info?.isPlaying ?? false)
        }
        provider.start()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        provider.stop()
    }

    func send(_ command: MediaCommand) {
        // Optimistic local update for snappy feedback, then let the provider
        // reconcile on its next notification.
        if case .playPause = command, var info = model.nowPlaying {
            info.isPlaying.toggle()
            baseElapsed = info.elapsed
            baseInstant = Date()
            model.nowPlaying = info
            updateTicker(playing: info.isPlaying)
        }
        provider.send(command)
    }

    private func updateTicker(playing: Bool) {
        ticker?.invalidate()
        guard playing else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, var info = self.model.nowPlaying, info.isPlaying else { return }
                let projected = self.baseElapsed + Date().timeIntervalSince(self.baseInstant)
                info.elapsed = min(info.duration, projected)
                self.model.nowPlaying = info
            }
        }
    }
}
