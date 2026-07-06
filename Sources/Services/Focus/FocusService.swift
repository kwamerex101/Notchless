import Foundation

/// Best-effort Focus-mode watcher. Reads the DoNotDisturb assertions file and
/// reports the active mode. Requires Full Disk Access and is fragile across OS
/// versions — degrades silently if the file is unreadable. See PLAN.md §5.
@MainActor
final class FocusService {
    var onChange: ((_ modeName: String?) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var lastMode: String?

    private var assertionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    }

    func start() {
        read()
        watch()
    }

    private func watch() {
        let fd = open(assertionsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main
        )
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.read() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func read() {
        guard let data = try? Data(contentsOf: assertionsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { emit(nil); return }

        // Structure: { "data": [ { "storeAssertionRecords": [ { "assertionDetails": { "assertionDetailsModeIdentifier": "com.apple.focus.work" } } ] } ] }
        let data0 = (json["data"] as? [[String: Any]])?.first
        let records = data0?["storeAssertionRecords"] as? [[String: Any]]
        let details = records?.first?["assertionDetails"] as? [String: Any]
        let identifier = details?["assertionDetailsModeIdentifier"] as? String
        emit(identifier.map(Self.friendlyName))
    }

    private func emit(_ mode: String?) {
        guard mode != lastMode else { return }
        lastMode = mode
        onChange?(mode)
    }

    private static func friendlyName(_ identifier: String) -> String {
        // "com.apple.focus.work" → "Work"
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}
