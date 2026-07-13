import Foundation

/// Third-party CLI that can control external-display brightness. We
/// deliberately do NOT implement our own DDC/I2C — MediaMate-style delegation
/// to whichever of these is installed (see PLAN.md grill decision).
enum ExternalBrightnessTool: String {
    case betterDisplay
    case lunar
}

/// Delegates EXTERNAL-display brightness writes to the BetterDisplay or Lunar
/// CLI, whichever is installed. Detection + the actual `Process` invocation
/// are best-effort and on-device (there's no way to unit test "is this CLI
/// actually installed and does it do what its docs say" in CI); the command
/// STRUCTURE is pure and unit-tested (see `ExternalBrightnessTests`).
///
/// `setExternalBrightness` is not yet called anywhere — it's wired up by the
/// interactive-drag phase (P5), which will call it as the user drags the
/// brightness HUD on an external display.
final class ExternalBrightnessBridge {
    static let shared = ExternalBrightnessBridge()

    // Paths are the tuning seam — adjust on-device if the tools live elsewhere.
    static let lunarCLIPath = "/usr/local/bin/lunar"
    static let betterDisplayCLIPaths = ["/usr/local/bin/betterdisplaycli",
                                        "/opt/homebrew/bin/betterdisplaycli"]

    private init() {}

    /// The installed tool, if any (prefers BetterDisplay, then Lunar). nil = neither installed.
    func detectTool() -> ExternalBrightnessTool? {
        if betterDisplayExecutablePath() != nil { return .betterDisplay }
        if FileManager.default.isExecutableFile(atPath: Self.lunarCLIPath) { return .lunar }
        return nil
    }

    private func betterDisplayExecutablePath() -> String? {
        Self.betterDisplayCLIPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// PURE — builds the command for a tool. UNIT-TESTED. `level` is 0...1
    /// (out-of-range values are clamped before being embedded in the command).
    /// This is the single place to fix CLI syntax on-device.
    ///
    /// // TUNE ON-DEVICE: the exact flag names/format for both CLIs below are
    /// best-effort guesses based on published docs, not verified against a
    /// real install. Confirm against `lunar --help` / `betterdisplaycli --help`
    /// and adjust here — this is the only place that needs to change.
    static func command(for tool: ExternalBrightnessTool, level: Double,
                         displayArg: String) -> (launchPath: String, args: [String]) {
        let clamped = min(max(level, 0), 1)
        switch tool {
        case .lunar:
            let percent = Int((clamped * 100).rounded())
            return (lunarCLIPath, ["displays", displayArg, "brightness", "\(percent)"])
        case .betterDisplay:
            // Canonical launch path for the pure builder — the first entry in
            // betterDisplayCLIPaths. `setExternalBrightness` below substitutes
            // whichever path `detectTool()` actually found on disk.
            return (betterDisplayCLIPaths[0], ["set", "-brightness=\(clamped)", "-display=\(displayArg)"])
        }
    }

    /// Best-effort external write. Clamps level. No-op → false if no tool installed.
    /// Runs off the main thread (fire-and-forget). Returns whether a command
    /// was launched, NOT whether brightness actually changed.
    @discardableResult
    func setExternalBrightness(_ level: Double, displayArg: String = "main") -> Bool {
        guard let tool = detectTool() else { return false }
        var (launchPath, args) = Self.command(for: tool, level: level, displayArg: displayArg)
        if tool == .betterDisplay, let resolvedPath = betterDisplayExecutablePath() {
            launchPath = resolvedPath
        }

        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.launchPath = launchPath
            task.arguments = args
            try? task.run()
        }
        return true
    }
}
