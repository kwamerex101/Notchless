import Foundation
import Combine

/// A single past dictation.
struct DictationRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
}

/// Lightweight recent-dictation history, persisted as JSON with a retention
/// window. (ListenToMe uses SQLite + encryption; this is the lean equivalent.)
@MainActor
final class DictationHistory: ObservableObject {
    static let shared = DictationHistory()

    @Published private(set) var records: [DictationRecord] = []

    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchless", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("dictation-history.json")
        load()
    }

    func add(_ text: String, retentionDays: Int) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        records.insert(DictationRecord(text: clean, date: Date()), at: 0)
        enforceRetention(days: retentionDays)
        save()
    }

    func remove(_ record: DictationRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    private func enforceRetention(days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        records.removeAll { $0.date < cutoff }
        if records.count > 500 { records = Array(records.prefix(500)) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DictationRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
