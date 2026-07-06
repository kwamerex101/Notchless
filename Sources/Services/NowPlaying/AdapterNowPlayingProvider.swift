import AppKit

/// Now-playing provider backed by the bundled mediaremote-adapter
/// (github.com/ungive/mediaremote-adapter, BSD-3-Clause). Runs the system Perl
/// binary — which is entitled to use MediaRemote — as a subprocess and parses
/// its JSON stream, so it works on macOS 15.4+ where direct MediaRemote calls
/// are gated. See STATUS.md and Resources/Adapter/.
@MainActor
final class AdapterNowPlayingProvider: NowPlayingProvider {
    var onChange: ((NowPlayingInfo?) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var lastPayload: [String: Any] = [:]

    /// True when the adapter files are present in the bundle.
    static var isBundled: Bool { paths() != nil }

    private static func paths() -> (perlScript: String, framework: String)? {
        guard let resource = Bundle.main.resourceURL else { return nil }
        let dir = resource.appendingPathComponent("Adapter")
        let script = dir.appendingPathComponent("mediaremote-adapter.pl")
        let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
        let fm = FileManager.default
        guard fm.fileExists(atPath: script.path), fm.fileExists(atPath: framework.path) else { return nil }
        return (script.path, framework.path)
    }

    func start() {
        guard let paths = Self.paths() else { onChange?(nil); return }
        Self.killStaleStreams(scriptPath: paths.perlScript)
        launchStream(paths)
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// A hard-killed prior run can leave the perl stream orphaned (reparented to
    /// launchd). Sweep any lingering streams for *our* script before starting a
    /// fresh one. Matching the full bundle-specific path avoids touching other
    /// apps' adapters.
    private static func killStaleStreams(scriptPath: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", scriptPath]
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    func send(_ command: MediaCommand) {
        guard let paths = Self.paths() else { return }
        switch command {
        case .playPause: runOneShot(paths, ["send", "2"])   // kMRATogglePlayPause
        case .next: runOneShot(paths, ["send", "4"])        // kMRANextTrack
        case .previous: runOneShot(paths, ["send", "5"])    // kMRAPreviousTrack
        case .toggleShuffle: runOneShot(paths, ["shuffle", "3"]) // tracks
        case let .seek(seconds): runOneShot(paths, ["seek", String(Int(seconds))])
        }
    }

    // MARK: - Streaming

    private func launchStream(_ paths: (perlScript: String, framework: String)) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // `stream` emits diffs by default; `--now` is a get-only option. Elapsed
        // arrives as `elapsedTime`; MediaController interpolates between updates.
        task.arguments = [paths.perlScript, paths.framework, "stream", "--debounce=250"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.ingest(chunk) }
        }

        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.process = nil
                // Auto-restart after a short delay if we didn't intentionally stop.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self?.process == nil, self?.onChange != nil {
                    self?.start()
                }
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            onChange?(nil)
        }
    }

    /// Accumulate bytes and process complete newline-delimited JSON objects.
    private func ingest(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handleLine(line)
        }
    }

    private func handleLine(_ line: Data) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data"
        else { return }

        let isDiff = object["diff"] as? Bool ?? false
        let payload = object["payload"] as? [String: Any] ?? [:]

        if isDiff {
            lastPayload.merge(payload) { _, new in new }
        } else {
            lastPayload = payload
        }

        onChange?(Self.parse(lastPayload))
    }

    // MARK: - Parsing

    private static func parse(_ p: [String: Any]) -> NowPlayingInfo? {
        guard let title = p["title"] as? String, !title.isEmpty else { return nil }

        let artist = p["artist"] as? String ?? ""
        let album = p["album"] as? String
        let duration = (p["duration"] as? NSNumber)?.doubleValue ?? 0
        // "--now" adds an interpolated elapsed value under elapsedTimeNow.
        let elapsed = (p["elapsedTimeNow"] as? NSNumber)?.doubleValue
            ?? (p["elapsedTime"] as? NSNumber)?.doubleValue ?? 0
        let playing = (p["playing"] as? NSNumber)?.boolValue ?? false

        var artwork: NSImage?
        if let base64 = p["artworkData"] as? String,
           let data = Data(base64Encoded: base64) {
            artwork = NSImage(data: data)
        }

        return NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            isPlaying: playing,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: p["bundleIdentifier"] as? String,
            appName: p["parentApplicationBundleIdentifier"] as? String
        )
    }

    // MARK: - One-shot commands

    private func runOneShot(_ paths: (perlScript: String, framework: String), _ args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [paths.perlScript, paths.framework] + args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
