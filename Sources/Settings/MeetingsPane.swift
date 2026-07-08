import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MeetingsPane: View {
    @ObservedObject var meeting: MeetingController
    @AppStorage("meeting.enabled") private var enabled = false
    @AppStorage("meeting.summarizerModel") private var model = "claude-sonnet-5"
    @AppStorage("meeting.deleteAudio") private var deleteAudio = true
    @AppStorage("hasSeenMeetingConsentNotice") private var seenConsent = false
    @State private var selection: UUID?
    @State private var showConsent = false

    var body: some View {
        Form {
            Section("Meetings") {
                List(meeting.records, selection: $selection) { rec in
                    VStack(alignment: .leading) {
                        Text(rec.title)
                        Text(rec.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let id = selection, let rec = meeting.records.first(where: { $0.id == id }) {
                Section("Details") {
                    if let m = rec.minutes { Text(m.summary) }
                    ForEach(rec.transcript.segments.indices, id: \.self) { i in
                        let s = rec.transcript.segments[i]
                        Text("\(s.speaker.displayName(rec.speakerNames)): \(s.text)")
                    }
                    HStack {
                        Button("Re-run summary") { meeting.rerunSummary(id: id) }
                        Button("Export Markdown…") { export(rec) }
                        Button("Delete", role: .destructive) { meeting.delete(id: id) }
                    }
                }
            }
            Section("Settings") {
                Toggle("Enable meeting capture", isOn: Binding(
                    get: { enabled },
                    set: { newValue in
                        if newValue && !seenConsent { showConsent = true }   // consent gate on first enable
                        else { enabled = newValue }
                    }))
                Picker("Summary model", selection: $model) {
                    Text("Sonnet 5 (balanced)").tag("claude-sonnet-5")
                    Text("Haiku 4.5 (cheap)").tag("claude-haiku-4-5")
                    Text("Opus 4.8 (best)").tag("claude-opus-4-8")
                }
                Toggle("Delete audio after processing", isOn: $deleteAudio)
            }
        }
        .sheet(isPresented: $showConsent) {
            MeetingConsentSheet(
                onAgree: { seenConsent = true; enabled = true; showConsent = false },
                onCancel: { showConsent = false })
        }
    }

    private func export(_ rec: MeetingRecord) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(rec.title).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let md = MeetingStore(directory: MeetingStore.defaultDirectory()).markdown(for: rec)
        try? md.data(using: .utf8)?.write(to: url)
    }
}

/// One-time consent sheet: recording all parties is the user's responsibility.
struct MeetingConsentSheet: View {
    let onAgree: () -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Meeting capture").font(.headline)
            Text("This records audio from your microphone and everyone else on the call. "
               + "Recording other people may require their consent depending on where you and "
               + "they are located. You are responsible for obtaining any required consent.")
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("I understand", action: onAgree).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
