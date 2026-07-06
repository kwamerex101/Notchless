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

    /// Re-writes the file in the new encryption state (called when the toggle
    /// flips), so existing records aren't lost.
    func reencrypt(encrypted: Bool) {
        save(forceEncrypted: encrypted)
    }

    private var wantsEncryption: Bool { DictationSettings.shared.encryptHistory }

    private func load() {
        guard let raw = try? Data(contentsOf: url) else { return }
        // Try plaintext JSON first; if that fails, try decrypting.
        if let decoded = try? JSONDecoder().decode([DictationRecord].self, from: raw) {
            records = decoded
        } else if let plain = HistoryCipher.decrypt(raw),
                  let decoded = try? JSONDecoder().decode([DictationRecord].self, from: plain) {
            records = decoded
        }
    }

    private func save(forceEncrypted: Bool? = nil) {
        guard let json = try? JSONEncoder().encode(records) else { return }
        let encrypt = forceEncrypted ?? wantsEncryption
        let data = encrypt ? (HistoryCipher.encrypt(json) ?? json) : json
        try? data.write(to: url, options: .atomic)
    }
}
