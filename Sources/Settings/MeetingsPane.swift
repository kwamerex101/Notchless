import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum MeetingTab: String, CaseIterable, Identifiable {
    case library, settings
    var id: String { rawValue }
    var title: String { self == .library ? "Meetings" : "Settings" }
}

struct MeetingsPane: View {
    @ObservedObject var meeting: MeetingController
    @AppStorage("meeting.enabled") private var enabled = false
    @AppStorage("meeting.summarizerBackend") private var backend = MeetingSummaryBackend.subscription.rawValue
    @AppStorage("meeting.summarizerModel") private var model = "claude-sonnet-5"
    @AppStorage("meeting.deleteAudio") private var deleteAudio = true
    @AppStorage("hasSeenMeetingConsentNotice") private var seenConsent = false
    @State private var tab: MeetingTab = .library
    @State private var selection: UUID?
    @State private var showConsent = false

    private var cliAvailable: Bool { ClaudeCLIMinutesClient.isAvailable() }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .meetings)

            SegmentedControl(options: MeetingTab.allCases, selection: $tab) { $0.title }

            switch tab {
            case .library:  libraryTab
            case .settings: settingsTab
            }
        }
        .sheet(isPresented: $showConsent) {
            MeetingConsentSheet(
                onAgree: { seenConsent = true; enabled = true; showConsent = false },
                onCancel: { showConsent = false })
        }
    }

    // MARK: - Settings tab

    @ViewBuilder private var settingsTab: some View {
        SectionLabel("Recording")
        CardGroup {
            ToggleRow(title: "Enable meeting capture", isOn: enableBinding, systemImage: "record.circle")
            CardDivider()
            ToggleRow(title: "Delete audio after processing", isOn: $deleteAudio, systemImage: "trash")
            CardDivider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "headphones").foregroundStyle(SettingsTheme.textSecondary).frame(width: 18)
                Footnote("Start a meeting from the notch once enabled. Wear headphones for clean speaker separation — otherwise your mic captures everyone and all speech is labelled “You”.")
            }
        }

        SectionLabel("AI summary")
        CardGroup {
            MenuRow(title: "Summarize via", options: MeetingSummaryBackend.allCases, selection: backendBinding) { $0.title }
            if backend == MeetingSummaryBackend.subscription.rawValue {
                CardDivider()
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: cliAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(cliAvailable ? SettingsTheme.statusGranted : NotchTheme.warning).frame(width: 18)
                    Footnote(cliAvailable
                         ? "Using your Claude subscription via the claude CLI — no API key or per-token cost."
                         : "The claude CLI wasn’t found. Install Claude Code and sign in, or switch to an Anthropic API key.")
                }
            } else {
                CardDivider()
                FlatSecureField(placeholder: "Anthropic API key", text: keyBinding)
                Footnote("Stored in your Keychain, shared with Dictation’s AI cleanup. Billed per token to your Anthropic account.")
            }
            CardDivider()
            MenuRow(title: "Model", options: ["claude-sonnet-5", "claude-haiku-4-5", "claude-opus-4-8"], selection: $model) { Self.modelName($0) }
        }
    }

    // MARK: - Library tab

    @ViewBuilder private var libraryTab: some View {
        if meeting.records.isEmpty {
            CardGroup {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 30)).foregroundStyle(SettingsTheme.textSecondary)
                    Text("No meetings yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsTheme.text)
                    Text(enabled
                         ? "Start one from the notch — the record control is live."
                         : "Enable meeting capture in Settings, then start one from the notch.")
                        .font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
            }
        } else {
            CardGroup {
                ForEach(Array(meeting.records.enumerated()), id: \.element.id) { idx, rec in
                    if idx > 0 { CardDivider() }
                    meetingRow(rec)
                }
            }
            if let id = selection, let rec = meeting.records.first(where: { $0.id == id }) {
                detail(for: rec, id: id)
            }
        }
    }

    private func meetingRow(_ rec: MeetingRecord) -> some View {
        Button { selection = (selection == rec.id) ? nil : rec.id } label: {
            HStack(spacing: 10) {
                Image(systemName: selection == rec.id ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary).frame(width: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.title).font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
                    Text("\(rec.date, style: .date) · \(durationText(rec.duration))")
                        .font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
                }
                Spacer()
                if rec.summaryFailed {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NotchTheme.warning)
                } else if rec.minutes != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(SettingsTheme.statusGranted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected-meeting detail

    @ViewBuilder private func detail(for rec: MeetingRecord, id: UUID) -> some View {
        SectionLabel("Summary")
        CardGroup {
            if let m = rec.minutes {
                Text(m.summary).font(.system(size: 13)).foregroundStyle(SettingsTheme.text).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !m.decisions.isEmpty {
                    CardDivider()
                    SectionLabel("Decisions")
                    ForEach(m.decisions.indices, id: \.self) { i in bullet(m.decisions[i]) }
                }
                if !m.actionItems.isEmpty {
                    CardDivider()
                    SectionLabel("Action items")
                    ForEach(m.actionItems.indices, id: \.self) { i in
                        let a = m.actionItems[i]
                        bullet(a.text + (a.owner.map { " — \($0.displayName(rec.speakerNames))" } ?? ""))
                    }
                }
            } else if rec.summaryFailed {
                Label("Summary failed", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13)).foregroundStyle(NotchTheme.warning)
                if let reason = meeting.summaryError {
                    Text(reason).font(.system(size: 11)).foregroundStyle(NotchTheme.warning).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Footnote("The transcript is saved. Fix the cause (or switch backend in Settings) and Re-run below.")
            } else if meeting.phase == .summarizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…").font(.system(size: 13)).foregroundStyle(SettingsTheme.textSecondary)
                }
            } else {
                Text("No summary yet.").font(.system(size: 13)).foregroundStyle(SettingsTheme.textSecondary)
            }
        }

        speakersCard(for: rec)

        SectionLabel("Transcript")
        CardGroup {
            ForEach(rec.transcript.segments.indices, id: \.self) { i in
                let s = rec.transcript.segments[i]
                HStack(alignment: .top, spacing: 10) {
                    Text(s.speaker.displayName(rec.speakerNames))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(speakerColor(s.speaker))
                        .frame(width: 68, alignment: .leading)
                    Text(s.text).font(.system(size: 13)).foregroundStyle(SettingsTheme.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }

        HStack(spacing: 8) {
            FlatButton(title: "Re-run summary") { meeting.rerunSummary(id: id) }
            FlatButton(title: "Export Markdown") { export(rec) }
            Spacer()
            FlatButton(title: "Delete", style: .destructive) { meeting.delete(id: id); selection = nil }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private func speakersCard(for rec: MeetingRecord) -> some View {
        let remoteIds = Array(NSOrderedSet(array: rec.transcript.segments.compactMap {
            if case let .remote(id, _) = $0.speaker { return id }; return nil
        })) as? [String] ?? []
        if !remoteIds.isEmpty {
            SectionLabel("Speakers")
            CardGroup {
                ForEach(remoteIds.indices, id: \.self) { i in
                    if i > 0 { CardDivider() }
                    let rid = remoteIds[i]
                    HStack(spacing: 10) {
                        Circle().fill(speakerColor(.remote(id: rid, name: nil))).frame(width: 8, height: 8)
                        Text(Speaker.remote(id: rid, name: nil).displayName(rec.speakerNames))
                            .font(.system(size: 12))
                            .frame(width: 78, alignment: .leading).foregroundStyle(SettingsTheme.textSecondary)
                        FlatTextField(placeholder: "Name", text: Binding(
                            get: { rec.speakerNames[rid] ?? "" },
                            set: { meeting.rename(id: rec.id, remoteId: rid, to: $0) }))
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var enableBinding: Binding<Bool> {
        Binding(get: { enabled }, set: { newValue in
            if newValue && !seenConsent { showConsent = true } else { enabled = newValue }
        })
    }
    private var backendBinding: Binding<MeetingSummaryBackend> {
        Binding(get: { MeetingSummaryBackend(rawValue: backend) ?? .subscription },
                set: { backend = $0.rawValue })
    }
    private var keyBinding: Binding<String> {
        Binding(get: { DictationSettings.shared.anthropicAPIKey },
                set: { DictationSettings.shared.anthropicAPIKey = $0 })
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").font(.system(size: 13)).foregroundStyle(SettingsTheme.textSecondary)
            Text(text).font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    /// Distinguishes speakers by hue — not a semantic colour from the token
    /// set, but a legend that needs several visually-distinct values.
    private func speakerColor(_ s: Speaker) -> Color {
        if case .you = s { return NotchTheme.link }
        if case let .remote(id, _) = s {
            let palette: [Color] = [NotchTheme.positive, NotchTheme.warning, NotchTheme.focus, .pink, .teal, .indigo]
            return palette[abs(id.hashValue) % palette.count]
        }
        return SettingsTheme.textSecondary
    }

    private func durationText(_ d: TimeInterval) -> String {
        let m = Int(d) / 60, s = Int(d) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private static func modelName(_ id: String) -> String {
        if id.contains("haiku") { return "Haiku (fast)" }
        if id.contains("opus") { return "Opus (best)" }
        return "Sonnet (balanced)"
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
            Label("Meeting capture", systemImage: "person.2.wave.2.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(SettingsTheme.text)
            Text("This records audio from your microphone and everyone else on the call. "
               + "Recording other people may require their consent depending on where you and "
               + "they are located. You are responsible for obtaining any required consent.")
                .font(.system(size: 13)).foregroundStyle(SettingsTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(SettingsTheme.text)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.button))
                Button("I understand", action: onAgree)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(SettingsTheme.onPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.primaryFill))
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(SettingsTheme.windowBody)
    }
}
