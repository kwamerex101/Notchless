import Foundation

/// Optional transcript polish via the local `claude` CLI (reuses the user's
/// Claude Code auth). Pure subprocess — no bundled model. Returns the original
/// text unchanged if the CLI isn't available or anything goes wrong, so the raw
/// transcript always stands. (ListenToMe also offers a local Gemma path; that
/// needs the llama.cpp native bridge and is a later phase.)
enum TranscriptCleaner {
    /// Whether cleanup should run for this transcript, given the mode.
    static func shouldClean(_ text: String, mode: DictationCleanup) -> Bool {
        switch mode {
        case .off: return false
        case .always: return true
        case .smart: return text.split(separator: " ").count > 20
        }
    }

    static func clean(_ text: String) async -> String {
        guard let cli = claudePath() else { return text }
        let prompt = """
        Clean up this dictated transcript: fix punctuation, capitalization, and \
        obvious speech-to-text errors. Do NOT rewrite, summarize, translate, or \
        add commentary — return only the corrected text.
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["--print", "--model", "haiku",
                             "--output-format", "text", "--append-system-prompt", prompt]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            stdin.fileHandleForWriting.write(Data(text.utf8))
            try? stdin.fileHandleForWriting.close()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return text }
            let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? text : out
        } catch {
            return text
        }
    }

    private static func claudePath() -> String? {
        for path in ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                     (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/claude")] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
