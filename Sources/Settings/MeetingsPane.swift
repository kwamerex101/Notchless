import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MeetingsPane: View {
    @ObservedObject var meeting: MeetingController
    @AppStorage("meeting.enabled") private var enabled = false
    @AppStorage("meeting.summarizerBackend") private var backend = MeetingSummaryBackend.subscription.rawValue
    @AppStorage("meeting.summarizerModel") private var model = "claude-sonnet-5"
    @AppStorage("meeting.deleteAudio") private var deleteAudio = true
    @AppStorage("hasSeenMeetingConsentNotice") private var seenConsent = false
    @State private var selection: UUID?
    @State private var showConsent = false

    private var cliAvailable: Bool { ClaudeCLIMinutesClient.isAvailable() }

    var body: some View {
        Form {
            recordingSection
            aiSummarySection
            librarySection
            if let id = selection, let rec = meeting.records.first(where: { $0.id == id }) {
                summarySection(for: rec, id: id)
                speakersSection(for: rec)
                transcriptSection(for: rec)
                actionsSection(for: rec, id: id)
            }
        }
        .sheet(isPresented: $showConsent) {
            MeetingConsentSheet(
                onAgree: { seenConsent = true; enabled = true; showConsent = false },
                onCancel: { showConsent = false })
        }
    }

    // MARK: - Recording

    private var recordingSection: some View {
        Section("Recording") {
            Toggle("Enable meeting capture", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    if newValue && !seenConsent { showConsent = true }   // consent gate on first enable
                    else { enabled = newValue }
                }))
            Toggle("Delete audio after processing", isOn: $deleteAudio)
            Text("With the record control enabled, start a meeting from the notch. For clean speaker separation, wear headphones — otherwise your mic captures everyone and all speech is labelled “You”.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI summary backend

    private var aiSummarySection: some View {
        Section("AI summary") {
            Picker("Summarize via", selection: $backend) {
                ForEach(MeetingSummaryBackend.allCases) { b in Text(b.title).tag(b.rawValue) }
            }
            if backend == MeetingSummaryBackend.subscription.rawValue {
                Label(cliAvailable
                      ? "Using your Claude subscription via the claude CLI — no API key or per-token cost."
                      : "The claude CLI wasn’t found. Install Claude Code and sign in, or switch to an Anthropic API key.",
                      systemImage: cliAvailable ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(cliAvailable ? Color.secondary : Color.orange)
            } else {
                SecureField("Anthropic API key", text: Binding(
                    get: { DictationSettings.shared.anthropicAPIKey },
                    set: { DictationSettings.shared.anthropicAPIKey = $0 }))
                Text("Stored in your Keychain and shared with Dictation’s AI cleanup. Billed per token to your Anthropic account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Model", selection: $model) {
                Text("Sonnet (balanced)").tag("claude-sonnet-5")
                Text("Haiku (cheap/fast)").tag("claude-haiku-4-5")
                Text("Opus (best)").tag("claude-opus-4-8")
            }
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        Section("Meetings") {
            if meeting.records.isEmpty {
                Text("No meetings yet — enable capture and start one from the notch.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(meeting.records) { rec in
                    Button { selection = (selection == rec.id) ? nil : rec.id } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rec.title)
                                Text(rec.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if rec.summaryFailed {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            }
                            if selection == rec.id {
                                Image(systemName: "chevron.down").foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Selected-meeting detail

    @ViewBuilder
    private func summarySection(for rec: MeetingRecord, id: UUID) -> some View {
        Section("Summary") {
            if let m = rec.minutes {
                Text(m.summary).textSelection(.enabled)
                if !m.decisions.isEmpty {
                    Text("Decisions").font(.caption).foregroundStyle(.secondary)
                    ForEach(m.decisions.indices, id: \.self) { i in Text("• \(m.decisions[i])") }
                }
                if !m.actionItems.isEmpty {
                    Text("Action items").font(.caption).foregroundStyle(.secondary)
                    ForEach(m.actionItems.indices, id: \.self) { i in
                        let a = m.actionItems[i]
                        Text("• \(a.text)\(a.owner.map { " — \($0.displayName(rec.speakerNames))" } ?? "")")
                    }
                }
            } else if rec.summaryFailed {
                Label("Summary failed", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                if let reason = meeting.summaryError {
                    Text(reason).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                Text("The transcript was saved. Fix the cause above (or switch backend) and use Re-run summary below.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No summary yet.").foregroundStyle(.secondary)
            }
        }
    }

    /// Editable name rows for each distinct remote speaker id in the transcript.
    @ViewBuilder
    private func speakersSection(for rec: MeetingRecord) -> some View {
        let remoteIds = Array(NSOrderedSet(array: rec.transcript.segments.compactMap {
            if case let .remote(id, _) = $0.speaker { return id }; return nil
        })) as? [String] ?? []
        if !remoteIds.isEmpty {
            Section("Speakers") {
                ForEach(remoteIds, id: \.self) { rid in
                    HStack {
                        Text(Speaker.remote(id: rid, name: nil).displayName(rec.speakerNames))
                            .frame(width: 90, alignment: .leading)
                        TextField("Name", text: Binding(
                            get: { rec.speakerNames[rid] ?? "" },
                            set: { meeting.rename(id: rec.id, remoteId: rid, to: $0) }))
                    }
                }
            }
        }
    }

    private func transcriptSection(for rec: MeetingRecord) -> some View {
        Section("Transcript") {
            ForEach(rec.transcript.segments.indices, id: \.self) { i in
                let s = rec.transcript.segments[i]
                Text("\(s.speaker.displayName(rec.speakerNames)): \(s.text)")
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }

    private func actionsSection(for rec: MeetingRecord, id: UUID) -> some View {
        Section {
            HStack {
                Button("Re-run summary") { meeting.rerunSummary(id: id) }
                Button("Export Markdown…") { export(rec) }
                Spacer()
                Button("Delete", role: .destructive) {
                    meeting.delete(id: id)
                    selection = nil
                }
            }
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
