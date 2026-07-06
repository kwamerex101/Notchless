import Foundation

/// Minimal append-only file logger for the dictation pipeline, so a session can
/// be watched live with `tail -f`. Writes to
/// ~/Library/Application Support/Notchless/dictation.log.
enum DictationLog {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchless", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictation.log")
    }()

    private static let queue = DispatchQueue(label: "com.rexdanquah.Notchless.dictationlog")

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
