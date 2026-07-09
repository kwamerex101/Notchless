import SwiftUI
import AppKit
import Speech
import AVFoundation

/// Top-level tabs within the Dictation pane.
enum DictationTab: String, CaseIterable, Identifiable {
    case settings, history, style
    var id: String { rawValue }
    var title: String {
        switch self {
        case .settings: return "Settings"
        case .history: return "History"
        case .style: return "Style"
        }
    }
}

struct DictationPane: View {
    @ObservedObject var settings = DictationSettings.shared
    @ObservedObject var dictionary = DictationDictionary.shared
    @ObservedObject var history = DictationHistory.shared
    @ObservedObject var snippets = DictationSnippets.shared
    @ObservedObject var parakeet = ParakeetModelStore.shared
    @ObservedObject var styles = StyleStore.shared
    @ObservedObject var llm = LLMModelStore.shared

    @State private var tab: DictationTab = .settings
    @State private var newTerm = ""
    @State private var newTrigger = ""
    @State private var newExpansion = ""
    @State private var editingRecord: DictationRecord?
    @State private var editingText = ""
    /// The row whose text was just copied, for a brief checkmark confirmation.
    @State private var copiedRecordID: DictationRecord.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(section: .dictation)

            Picker("", selection: $tab) {
                ForEach(DictationTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .settings: settingsTab
            case .history: historyTab
            case .style: styleTab
            }
        }
        .sheet(item: $editingRecord) { record in
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit dictation").font(.headline)
                TextEditor(text: $editingText)
                    .font(.body).frame(width: 360, height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                HStack {
                    Spacer()
                    Button("Cancel") { editingRecord = nil }
                    Button("Save") {
                        history.update(record, newText: editingText)
                        editingRecord = nil
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Settings tab

    @ViewBuilder private var settingsTab: some View {
        SectionLabel("General")
        CardGroup {
            ToggleRow(title: "Enable dictation", isOn: $settings.enabled)
            Divider()
            LabeledRow("Hotkey (hold to talk)") {
                SettingsPicker(options: DictationHotkeyOption.allCases, selection: $settings.hotkey) { $0.title }
            }
            Divider()
            LabeledRow("Language") {
                SettingsPicker(options: languages.map(\.id), selection: $settings.languageID) { languageName($0) }
            }
            Divider()
            LabeledRow("Microphone") {
                SettingsPicker(options: [""] + microphones.map(\.uid), selection: $settings.microphoneUID) { micName($0) }
            }
            Divider()
            LabeledRow("Max recording length") {
                Slider(value: Binding(
                    get: { Double(settings.maxRecordingSeconds) },
                    set: { settings.maxRecordingSeconds = Int($0) }
                ), in: 10...300, step: 10).frame(width: 150)
                Text("\(settings.maxRecordingSeconds)s").frame(width: 40, alignment: .trailing)
            }
            Divider()
            ToggleRow(title: "Sound cues", isOn: $settings.soundCues)
        }

        SectionLabel("Transcription engine")
        CardGroup {
            LabeledRow("Engine") {
                SettingsPicker(options: DictationEngine.allCases, selection: $settings.engine) { $0.title }
            }
            Text(settings.engine.detail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if settings.engine == .parakeet {
                Divider()
                ParakeetStatusRow(status: parakeet.status) { parakeet.preload() }
            }
        }

        SectionLabel("AI cleanup")
        CardGroup {
            LabeledRow("Polish transcript") {
                SettingsPicker(options: DictationCleanup.allCases, selection: $settings.cleanup) { $0.title }
            }
            Text("Smart cleans only longer transcripts that look like they need it; the raw text always stands if cleanup fails or times out.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if settings.cleanup != .off {
                Divider()
                LabeledRow("Backend") {
                    SettingsPicker(options: DictationCleanupBackend.allCases, selection: $settings.cleanupBackend) { $0.title }
                }
                Divider()
                LabeledRow("Intensity") {
                    SettingsPicker(options: DictationCleanupIntensity.allCases, selection: $settings.cleanupIntensity) { $0.title }
                }
                Divider()
                LabeledRow("Timeout") {
                    Slider(value: Binding(
                        get: { Double(settings.cleanupTimeoutSeconds) },
                        set: { settings.cleanupTimeoutSeconds = Int($0) }
                    ), in: 5...60, step: 5).frame(width: 150)
                    Text("\(settings.cleanupTimeoutSeconds)s").frame(width: 40, alignment: .trailing)
                }
                if settings.cleanupBackend == .api || settings.cleanupBackend == .auto {
                    Divider()
                    LabeledRow("Anthropic API key") {
                        SecureField("sk-ant-…", text: apiKeyBinding)
                            .textFieldStyle(.roundedBorder).frame(width: 220)
                    }
                    Text("Stored in your Keychain. Used by the API and Automatic backends; Automatic falls back to the Claude CLI when empty.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            ToggleRow(title: "Voice commands", isOn: $settings.voiceCommands)
            Text("Say “new line”, “new paragraph”, or “scratch that” to format as you speak. Formatting only — never runs shell or file actions.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ToggleRow(title: "Smart formatting", isOn: $settings.smartFormatting)
            Text("Turns spoken operators into symbols (“C plus plus” → C++), joins version numbers, and collapses accidental repeats.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if settings.cleanup != .off && settings.cleanupBackend == .onDevice {
            SectionLabel("On-device model")
            CardGroup {
                LabeledRow("Model") {
                    SettingsPicker(options: LocalLLMModel.allCases,
                                   selection: Binding(get: { llm.selected }, set: { llm.selected = $0 })) { $0.title }
                }
                Divider()
                GemmaStatusRow(status: llm.status, sizeText: llm.selected.sizeText,
                               download: { llm.download() }, delete: { llm.delete() })
                Text("Runs fully on-device with no network. Cleanup falls back to the raw transcript until the model is downloaded.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        SectionLabel("Output")
        CardGroup {
            SegmentedCards(
                options: DictationOutput.allCases,
                selection: $settings.output,
                title: { $0.title },
                systemImage: { $0.systemImage }
            )
            Divider()
            ToggleRow(title: "Auto-capitalize sentences", isOn: $settings.autoCapitalize)
        }

        SectionLabel("Snippets")
        CardGroup {
            HStack {
                TextField("Trigger (e.g. my email)", text: $newTrigger).textFieldStyle(.roundedBorder)
                TextField("Expands to…", text: $newExpansion).textFieldStyle(.roundedBorder)
                Button("Add", action: addSnippet).disabled(newTrigger.isEmpty || newExpansion.isEmpty)
            }
            ForEach(snippets.snippets) { snippet in
                Divider()
                HStack {
                    Text(snippet.trigger).font(.callout.weight(.medium))
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    Text(snippet.expansion).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button { snippets.remove(snippet) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
        }

        SectionLabel("Custom words")
        CardGroup {
            HStack {
                TextField("Add a term with exact casing (e.g. GitHub)", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)
                Button("Add", action: addTerm).disabled(newTerm.isEmpty)
            }
            if !dictionary.terms.isEmpty {
                Divider()
                FlowWrap(dictionary.terms) { term in
                    HStack(spacing: 4) {
                        Text(term).font(.callout)
                        Button { dictionary.remove(term) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
            }
        }
    }

    // MARK: - History tab

    @ViewBuilder private var historyTab: some View {
        SectionLabel("History")
        CardGroup {
            LabeledRow("Keep for") {
                Stepper("\(settings.historyRetentionDays) days", value: $settings.historyRetentionDays, in: 1...365)
                    .fixedSize()
            }
            Divider()
            ToggleRow(title: "Encrypt history at rest", isOn: $settings.encryptHistory)
        }

        SectionLabel("Recent dictations")
        CardGroup {
            if history.records.isEmpty {
                Text("No dictations yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(history.records.prefix(30)) { record in
                    HStack {
                        Text(record.text).lineLimit(2)
                        Spacer()
                        Button { copy(record) } label: {
                            Image(systemName: copiedRecordID == record.id ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copiedRecordID == record.id ? Color.green : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy")
                        Button { beginEditing(record) } label: {
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }.buttonStyle(.plain).help("Edit")
                        Button { history.remove(record) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain).help("Delete")
                    }
                    Divider()
                }
                Text("Edit a dictation to fix a word — correct the same word three times and it's added to your custom words automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Clear history", role: .destructive) { history.clear() }
                    .buttonStyle(.link)
            }
        }
    }

    // MARK: - Style tab

    @ViewBuilder private var styleTab: some View {
        SectionLabel("Personalization")
        CardGroup {
            ToggleRow(title: "Context-aware cleanup", isOn: $settings.contextAwareCleanup)
            Text("Tailors cleanup to the app you're dictating into — preserves code in editors, stays casual in chat — and learns each app's tone over time.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        SectionLabel("Per-app style")
        CardGroup {
            if styles.styles.isEmpty {
                Text("As you dictate into apps, Notchless learns each one's tone and suggests it here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let sorted = styles.styles.values.sorted { $0.sampleCount > $1.sampleCount }
                ForEach(sorted) { style in
                    StyleRow(style: style)
                    if style.id != sorted.last?.id { Divider() }
                }
            }
        }
    }

    // MARK: - Actions

    private func beginEditing(_ record: DictationRecord) {
        editingText = record.text
        editingRecord = record
    }

    /// Copy a past dictation to the clipboard, with a brief checkmark on its row.
    private func copy(_ record: DictationRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
        withAnimation { copiedRecordID = record.id }
        let id = record.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedRecordID == id { withAnimation { copiedRecordID = nil } }
        }
    }

    /// The Anthropic key lives in the Keychain, so bridge it through a manual
    /// binding rather than `$settings.…`.
    private var apiKeyBinding: Binding<String> {
        Binding(get: { settings.anthropicAPIKey }, set: { settings.anthropicAPIKey = $0 })
    }

    private func addTerm() {
        dictionary.add(newTerm)
        newTerm = ""
    }

    private func addSnippet() {
        snippets.add(trigger: newTrigger, expansion: newExpansion)
        newTrigger = ""
        newExpansion = ""
    }

    // MARK: - Enumerations

    private var languages: [(id: String, name: String)] {
        SFSpeechRecognizer.supportedLocales()
            .map { ($0.identifier, Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
            .sorted { $0.1 < $1.1 }
    }

    private func languageName(_ id: String) -> String {
        Locale.current.localizedString(forIdentifier: id) ?? id
    }

    private var microphones: [(uid: String, name: String)] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio, position: .unspecified
        ).devices.map { ($0.uniqueID, $0.localizedName) }
    }

    private func micName(_ uid: String) -> String {
        uid.isEmpty ? "System default" : (microphones.first { $0.uid == uid }?.name ?? uid)
    }
}

/// A label on the left, trailing controls flush to the right — matching the
/// toggle rows so every control lines up on the same right edge.
struct LabeledRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing

    init(_ label: String, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// A borderless dropdown that hugs its content and sits flush against the
/// trailing edge (no bezel inset like a bordered `Picker`), so it aligns with
/// the switch rows.
struct SettingsPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(title(option)) { selection = option }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title(selection)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Shows the on-device Gemma model's download state with download/delete.
struct GemmaStatusRow: View {
    let status: LLMModelStore.Status
    let sizeText: String
    let download: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch status {
            case .notDownloaded:
                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                Text("Model not downloaded (\(sizeText))").foregroundStyle(.secondary)
                Spacer()
                Button("Download", action: download)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
                Text("Downloading… \(Int(fraction * 100))%").foregroundStyle(.secondary)
                Spacer()
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Model ready").foregroundStyle(.secondary)
                Spacer()
                Button("Delete", role: .destructive, action: delete)
            case .failed(let message):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(message).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Retry", action: download)
            }
        }
        .font(.callout)
    }
}

/// One learned per-app tone: shows a suggestion to accept/dismiss, or the
/// applied tone with a menu to change/revert it.
struct StyleRow: View {
    let style: StyleStore.AppStyle
    @ObservedObject private var store = StyleStore.shared

    private var appName: String {
        guard !style.bundleID.isEmpty else { return "Unknown app" }
        return style.bundleID.split(separator: ".").last.map(String.init)?.capitalized ?? style.bundleID
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(appName).font(.callout.weight(.medium))
                Text("\(style.sampleCount) dictations").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let suggested = style.suggestedTone {
                Text("Use \(suggested.title)?").font(.caption).foregroundStyle(.secondary)
                Button("Yes") { store.accept(style.bundleID, tone: suggested) }
                Button("No") { store.dismissSuggestion(style.bundleID) }.buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                SettingsPicker(options: StyleTone.allCases,
                               selection: Binding(
                                get: { style.acceptedTone ?? .none },
                                set: { store.accept(style.bundleID, tone: $0) })) { $0.title }
            }
        }
    }
}

/// Shows the Parakeet model's download/load state with a download action.
struct ParakeetStatusRow: View {
    let status: ParakeetModelStore.Status
    let download: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch status {
            case .notLoaded:
                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                Text("Model not downloaded (~600 MB)").foregroundStyle(.secondary)
                Spacer()
                Button("Download", action: download)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
                Text("Downloading… \(Int(fraction * 100))%").foregroundStyle(.secondary)
                Spacer()
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Model ready").foregroundStyle(.secondary)
                Spacer()
            case .unsupported:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Requires an Apple Silicon Mac").foregroundStyle(.secondary)
                Spacer()
            case .failed(let message):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(message).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Retry", action: download)
            }
        }
        .font(.callout)
    }
}

/// A simple wrapping row of chips.
struct FlowWrap<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let content: (Data.Element) -> Content

    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

    var body: some View {
        // A lightweight wrap using a lazy grid of flexible columns.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(data), id: \.self) { content($0) }
        }
    }
}
