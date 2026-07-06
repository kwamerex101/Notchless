import AppKit
import Combine

/// Owns the active now-playing provider, pushes updates into the notch model,
/// and interpolates elapsed time between provider updates so the scrubber moves
/// smoothly while playing.
@MainActor
final class MediaController {
    private let model: NotchViewModel
    private let provider: NowPlayingProvider
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
            var info = info
            // Stamp the report instant so the view can extrapolate elapsed time
            // itself — no half-second model republish while playing.
            info?.elapsedAt = Date()
            // Re-extract the glow color only when the track changes, not on
            // every playback update.
            if info?.title != self.lastColorTitle {
                self.lastColorTitle = info?.title
                self.model.artworkColor = info?.artwork.flatMap(ColorExtractor.vibrantColor)
            }
            self.model.nowPlaying = info
        }
        provider.start()
    }

    func stop() {
        provider.stop()
    }

    func send(_ command: MediaCommand) {
        // Optimistic local update for snappy feedback, then let the provider
        // reconcile on its next notification.
        if case .playPause = command, var info = model.nowPlaying {
            // Freeze the position at the current extrapolated value before
            // toggling, so a pause stops the clock exactly where it looked.
            info.elapsed = info.elapsed(at: Date())
            info.elapsedAt = Date()
            info.isPlaying.toggle()
            model.nowPlaying = info
        }
        provider.send(command)
    }
}
