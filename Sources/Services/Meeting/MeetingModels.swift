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
            // Diarization ids look like "SPEAKER_01" and are 0-indexed; present
            // them 1-indexed to users (SPEAKER_00 -> "Speaker 1", SPEAKER_01 ->
            // "Speaker 2") via the trailing integer.
            if let n = Int(id.split(separator: "_").last.map(String.init) ?? "") {
                return "Speaker \(n + 1)"
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
    /// Set when summarization failed but the transcript was kept, so the UI can
    /// offer a retry. Defaulted (and `decodeIfPresent`) so records saved before
    /// this field still decode.
    var summaryFailed: Bool = false

    init(id: UUID, title: String, date: Date, duration: TimeInterval,
         transcript: MeetingTranscript, minutes: MeetingMinutes?,
         speakerNames: [String: String], summaryFailed: Bool = false) {
        self.id = id; self.title = title; self.date = date; self.duration = duration
        self.transcript = transcript; self.minutes = minutes
        self.speakerNames = speakerNames; self.summaryFailed = summaryFailed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        date = try c.decode(Date.self, forKey: .date)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        transcript = try c.decode(MeetingTranscript.self, forKey: .transcript)
        minutes = try c.decodeIfPresent(MeetingMinutes.self, forKey: .minutes)
        speakerNames = try c.decode([String: String].self, forKey: .speakerNames)
        summaryFailed = try c.decodeIfPresent(Bool.self, forKey: .summaryFailed) ?? false
    }
}

/// Two on-disk WAVs plus timing, produced by MeetingCaptureService.
struct MeetingRecording {
    var micURL: URL
    var remoteURL: URL
    var startedAt: Date
    var duration: TimeInterval
}
