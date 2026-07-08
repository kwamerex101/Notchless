import Foundation

final class MeetingStore {
    private let directory: URL
    private let fm = FileManager.default

    init(directory: URL) {
        self.directory = directory
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Notchless/Meetings", isDirectory: true)
    }

    func save(_ record: MeetingRecord) throws {
        let url = directory.appendingPathComponent("\(record.id.uuidString).json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(record).write(to: url, options: .atomic)
    }

    func load() throws -> [MeetingRecord] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? dec.decode(MeetingRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    func delete(id: UUID) throws {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    func deleteAudio(_ recording: MeetingRecording) {
        for url in [recording.micURL, recording.remoteURL] {
            try? fm.removeItem(at: url)
        }
    }

    func markdown(for record: MeetingRecord) -> String {
        var out = "# Meeting — \(record.title)\n\n"
        let fmtr = DateFormatter(); fmtr.dateStyle = .medium; fmtr.timeStyle = .short
        out += "_\(fmtr.string(from: record.date))_\n\n"
        if let m = record.minutes {
            out += "## Summary\n\n\(m.summary)\n\n"
            if !m.decisions.isEmpty {
                out += "## Decisions\n\n" + m.decisions.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
            }
            if !m.actionItems.isEmpty {
                out += "## Action items\n\n" + m.actionItems.map {
                    let who = $0.owner.map { " — \($0.displayName(record.speakerNames))" } ?? ""
                    return "- \($0.text)\(who)"
                }.joined(separator: "\n") + "\n\n"
            }
        }
        out += "## Transcript\n\n"
        for seg in record.transcript.segments {
            out += "**\(seg.speaker.displayName(record.speakerNames)):** \(seg.text)\n\n"
        }
        return out
    }
}
