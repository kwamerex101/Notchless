import Foundation

enum Speaker: Codable, Equatable, Hashable {
    case you
    case remote(id: String, name: String?)

    /// Human label. `names` maps a remote id (e.g. "SPEAKER_01") to a user-set name.
    func displayName(_ names: [String: String]) -> String {
        switch self {
        case .you:
            return "You"
        case let .remote(id, name):
            if let name, !name.isEmpty { return name }
            if let mapped = names[id], !mapped.isEmpty { return mapped }
            // Diarization ids look like "SPEAKER_01" — use the trailing integer
            // directly as the label (e.g. "SPEAKER_01" -> "Speaker 1").
            if let n = Int(id.split(separator: "_").last.map(String.init) ?? "") {
                return "Speaker \(n)"
            }
            return id
        }
    }
}

struct TranscriptSegment: Codable, Equatable {
    var speaker: Speaker
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var qualityScore: Double?
}

struct MeetingTranscript: Codable, Equatable {
    var segments: [TranscriptSegment]
    var duration: TimeInterval
}

struct ActionItem: Codable, Equatable {
    var text: String
    var owner: Speaker?
}

struct MeetingMinutes: Codable, Equatable {
    var summary: String
    var decisions: [String]
    var actionItems: [ActionItem]
}

struct MeetingRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var transcript: MeetingTranscript
    var minutes: MeetingMinutes?
    var speakerNames: [String: String]
}

/// Two on-disk WAVs plus timing, produced by MeetingCaptureService.
struct MeetingRecording {
    var micURL: URL
    var remoteURL: URL
    var startedAt: Date
    var duration: TimeInterval
}
