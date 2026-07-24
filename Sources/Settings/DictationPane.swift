import SwiftUI
import AppKit
import Speech
import AVFoundation

/// Top-level tabs within the Dictation pane.
enum DictationTab: String, CaseIterable, Identifiable {
    case settings, modes, history, style
    var id: String { rawValue }
    var title: String {
        switch self {
        case .settings: return "Settings"
        case .modes: return "Modes"
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
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .dictation)

            SegmentedControl(options: DictationTab.allCases, selection: $tab) { $0.title }

            switch tab {
            case .settings: settingsTab
            case .modes: ModesTab()
            case .history: historyTab
            case .style: styleTab
            }
        }
        .sheet(item: $editingRecord) { record in
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit dictation").font(.system(size: 14, weight: .semibold)).foregroundStyle(SettingsTheme.text)
                TextEditor(text: $editingText)
                    .font(.system(size: 13)).frame(width: 360, height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.insetField))
                HStack {
                    Spacer()
                    Button("Cancel") { editingRecord = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(SettingsTheme.text)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.button))
                    Button("Save") {
                        history.update(record, newText: editingText)
                        editingRecord = nil
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(SettingsTheme.onPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.primaryFill))
                }
            }
            .padding(20)
            .background(SettingsTheme.windowBody)
        }
    }

    // MARK: - Settings tab

    @ViewBuilder private var settingsTab: some View {
        SectionLabel("General")
        CardGroup {
            ToggleRow(title: "Enable dictation", isOn: $settings.enabled)
            CardDivider()
            MenuRow(title: "Hotkey (hold to talk)", options: DictationHotkeyOption.allCases, selection: $settings.hotkey) { $0.title }
            CardDivider()
            MenuRow(title: "Language", options: languages.map(\.id), selection: $settings.languageID) { languageName($0) }
            CardDivider()
            MenuRow(title: "Microphone", options: [""] + microphones.map(\.uid), selection: $settings.microphoneUID) { micName($0) }
            CardDivider()
            SliderRow(title: "Max recording length", value: maxRecordingBinding, range: 10...300, step: 10, valueText: { "\(Int($0))s" })
            CardDivider()
            ToggleRow(title: "Sound cues", isOn: $settings.soundCues)
        }

        SectionLabel("Transcription Engine")
        CardGroup {
            MenuRow(title: "Engine", options: DictationEngine.allCases, selection: $settings.engine) { $0.title }
            Footnote(settings.engine.detail)
            if settings.engine == .parakeet {
                CardDivider()
                ParakeetStatusRow(status: parakeet.status) { parakeet.preload() }
            }
        }

        SectionLabel("AI Cleanup")
        CardGroup {
            MenuRow(title: "Polish transcript", options: DictationCleanup.allCases, selection: $settings.cleanup) { $0.title }
            Footnote("Smart cleans only longer transcripts that look like they need it; the raw text always stands if cleanup fails or times out.")
            if settings.cleanup != .off {
                CardDivider()
                MenuRow(title: "Backend", options: DictationCleanupBackend.allCases, selection: $settings.cleanupBackend) { $0.title }
                CardDivider()
                MenuRow(title: "Intensity", options: DictationCleanupIntensity.allCases, selection: $settings.cleanupIntensity) { $0.title }
                CardDivider()
                SliderRow(title: "Timeout", value: cleanupTimeoutBinding, range: 5...60, step: 5, valueText: { "\(Int($0))s" })
                if settings.cleanupBackend == .api || settings.cleanupBackend == .auto {
                    CardDivider()
                    HStack(spacing: 10) {
                        Text("Anthropic API key").font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
                        Spacer()
                        FlatSecureField(placeholder: "sk-ant-…", text: apiKeyBinding).frame(width: 220)
                    }
                    Footnote("Stored in your Keychain. Used by the API and Automatic backends; Automatic falls back to the Claude CLI when empty.")
                }
            }
            CardDivider()
            ToggleRow(title: "Voice commands", isOn: $settings.voiceCommands)
            Footnote("Say “new line”, “new paragraph”, or “scratch that” to format as you speak. Formatting only — never runs shell or file actions.")
            CardDivider()
            ToggleRow(title: "Smart formatting", isOn: $settings.smartFormatting)
            Footnote("Turns spoken operators into symbols (“C plus plus” → C++), joins version numbers, and collapses accidental repeats.")
        }

        if settings.cleanup != .off && settings.cleanupBackend == .onDevice {
            SectionLabel("On-device model")
            CardGroup {
                MenuRow(title: "Model", options: LocalLLMModel.allCases,
                        selection: Binding(get: { llm.selected }, set: { llm.selected = $0 })) { $0.title }
                CardDivider()
                GemmaStatusRow(status: llm.status, sizeText: llm.selected.sizeText,
                               download: { llm.download() }, delete: { llm.delete() })
                Footnote("Runs fully on-device with no network. Cleanup falls back to the raw transcript until the model is downloaded.")
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
            CardDivider()
            ToggleRow(title: "Auto-capitalize sentences", isOn: $settings.autoCapitalize)
        }

        SectionLabel("Snippets")
        CardGroup {
            HStack(spacing: 8) {
                FlatTextField(placeholder: "Trigger (e.g. my email)", text: $newTrigger)
                FlatTextField(placeholder: "Expands to…", text: $newExpansion)
                FlatButton(title: "Add", action: addSnippet)
                    .disabled(newTrigger.isEmpty || newExpansion.isEmpty)
            }
            ForEach(snippets.snippets) { snippet in
                CardDivider()
                HStack(spacing: 8) {
                    Text(snippet.trigger).font(.system(size: 13, weight: .medium)).foregroundStyle(SettingsTheme.text)
                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
                    Text(snippet.expansion).font(.system(size: 13)).foregroundStyle(SettingsTheme.textSecondary).lineLimit(1)
                    Spacer()
                    Button { snippets.remove(snippet) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.textSecondary)
                    }.buttonStyle(.plain)
                }
            }
        }

        SectionLabel("Custom words")
        CardGroup {
            HStack(spacing: 8) {
                FlatTextField(placeholder: "Add a term with exact casing (e.g. GitHub)", text: $newTerm, onSubmit: addTerm)
                FlatButton(title: "Add", action: addTerm).disabled(newTerm.isEmpty)
            }
            if !dictionary.terms.isEmpty {
                CardDivider()
                FlowWrap(dictionary.terms) { term in
                    HStack(spacing: 4) {
                        Text(term).font(.system(size: 12)).foregroundStyle(SettingsTheme.text)
                        Button { dictionary.remove(term) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.textSecondary)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(SettingsTheme.controlChip))
                }
            }
        }
    }

    // MARK: - History tab

    @ViewBuilder private var historyTab: some View {
        SectionLabel("History")
        CardGroup {
            HStack(spacing: 10) {
                Text("Keep for").font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
                Spacer()
                Stepper("\(settings.historyRetentionDays) days", value: $settings.historyRetentionDays, in: 1...365)
                    .fixedSize()
                    .foregroundStyle(SettingsTheme.textSecondary)
            }
            CardDivider()
            ToggleRow(title: "Encrypt history at rest", isOn: $settings.encryptHistory)
        }

        SectionLabel("Recent dictations")
        CardGroup {
            if history.records.isEmpty {
                Text("No dictations yet.").font(.system(size: 13)).foregroundStyle(SettingsTheme.textSecondary)
            } else {
                ForEach(history.records.prefix(30)) { record in
                    HStack(spacing: 10) {
                        Text(record.text).font(.system(size: 13)).foregroundStyle(SettingsTheme.text).lineLimit(2)
                        Spacer()
                        Button { copy(record) } label: {
                            Image(systemName: copiedRecordID == record.id ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copiedRecordID == record.id ? SettingsTheme.statusGranted : SettingsTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy")
                        Button { beginEditing(record) } label: {
                            Image(systemName: "pencil").foregroundStyle(SettingsTheme.textSecondary)
                        }.buttonStyle(.plain).help("Edit")
                        Button { history.remove(record) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.textSecondary)
                        }.buttonStyle(.plain).help("Delete")
                    }
                    CardDivider()
                }
                Footnote("Edit a dictation to fix a word — correct the same word three times and it's added to your custom words automatically.")
                FlatButton(title: "Clear history", style: .destructive) { history.clear() }
            }
        }
    }

    // MARK: - Style tab

    @ViewBuilder private var styleTab: some View {
        SectionLabel("Personalization")
        CardGroup {
            ToggleRow(title: "Context-aware cleanup", isOn: $settings.contextAwareCleanup)
            Footnote("Tailors cleanup to the app you're dictating into — preserves code in editors, stays casual in chat — and learns each app's tone over time.")
        }

        SectionLabel("Per-app style")
        CardGroup {
            if styles.styles.isEmpty {
                Text("As you dictate into apps, Notchless learns each one's tone and suggests it here.")
                    .font(.system(size: 13)).foregroundStyle(SettingsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let sorted = styles.styles.values.sorted { $0.sampleCount > $1.sampleCount }
                ForEach(sorted) { style in
                    StyleRow(style: style)
                    if style.id != sorted.last?.id { CardDivider() }
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

    /// `SliderRow` works in `Double`; the setting is whole seconds.
    private var maxRecordingBinding: Binding<Double> {
        Binding(
            get: { Double(settings.maxRecordingSeconds) },
            set: { settings.maxRecordingSeconds = Int($0) }
        )
    }

    private var cleanupTimeoutBinding: Binding<Double> {
        Binding(
            get: { Double(settings.cleanupTimeoutSeconds) },
            set: { settings.cleanupTimeoutSeconds = Int($0) }
        )
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
///
/// Kept for `FeaturePanes.swift` and `OnboardingView.swift`, which still build
/// their own trailing controls with it; in-scope panes use `MenuRow` instead.
struct LabeledRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing

    init(_ label: String, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// A borderless dropdown that hugs its content and sits flush against the
/// trailing edge (no bezel inset like a bordered `Picker`), so it aligns with
/// the switch rows.
///
/// Kept for `FeaturePanes.swift` and `OnboardingView.swift`; in-scope panes
/// use `MenuRow`, the shared spec §5 "Menu picker" chip, instead.
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
            .foregroundStyle(SettingsTheme.textSecondary)
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
                Image(systemName: "arrow.down.circle").foregroundStyle(SettingsTheme.textSecondary)
                Text("Model not downloaded (\(sizeText))").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
                Spacer()
                FlatButton(title: "Download", action: download)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
                Text("Downloading… \(Int(fraction * 100))%").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
                Spacer()
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SettingsTheme.statusGranted)
                Text("Model ready").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
                Spacer()
                FlatButton(title: "Delete", style: .destructive, action: delete)
            case .failed(let message):
                Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.statusDenied)
                Text(message).font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary).lineLimit(1)
                Spacer()
                FlatButton(title: "Retry", action: download)
            }
        }
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
                Text(appName).font(.system(size: 13, weight: .medium)).foregroundStyle(SettingsTheme.text)
                Text("\(style.sampleCount) dictations").font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
            }
            Spacer()
            if let suggested = style.suggestedTone {
                Text("Use \(suggested.title)?").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
                Button("Yes") { store.accept(style.bundleID, tone: suggested) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(SettingsTheme.text)
                Button("No") { store.dismissSuggestion(style.bundleID) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
            } else {
                // A bare trailing chip menu — `MenuRow` always pairs a leading
                // label with its chip, which doesn't fit this row's layout.
                Menu {
                    ForEach(StyleTone.allCases, id: \.self) { tone in
                        Button(tone.title) { store.accept(style.bundleID, tone: tone) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text((style.acceptedTone ?? .none).title)
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.textSecondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(SettingsTheme.textSecondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.controlChip))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
                Image(systemName: "arrow.down.circle").foregroundStyle(SettingsTheme.textSecondary)
                Text("Model not downloaded (~600 MB)").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
                Spacer()
                FlatButton(title: "Download", action: download)
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
                Text("Downloading… \(Int(fraction * 100))%").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
                Spacer()
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SettingsTheme.statusGranted)
                Text("Model ready").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
                Spacer()
            case .unsupported:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NotchTheme.warning)
                Text("Requires an Apple Silicon Mac").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
                Spacer()
            case .failed(let message):
                Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.statusDenied)
                Text(message).font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary).lineLimit(1)
                Spacer()
                FlatButton(title: "Retry", action: download)
            }
        }
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

// MARK: - Flat text fields

/// Flat-dark text field: padding `6 10`, radius 8, `SettingsTheme.insetField`,
/// placeholder 12 `SettingsTheme.textPlaceholder`. Spec §5 "Text field".
/// Shared across the in-scope panes (Dictation, Meetings, Goals, Tasks).
struct FlatTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder)
            .foregroundColor(SettingsTheme.textPlaceholder)
            .font(.system(size: 12)))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(SettingsTheme.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.insetField))
            .onSubmit { onSubmit?() }
    }
}

/// `FlatTextField`'s secure-entry counterpart, for API keys.
struct FlatSecureField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField("", text: $text, prompt: Text(placeholder)
            .foregroundColor(SettingsTheme.textPlaceholder)
            .font(.system(size: 12)))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(SettingsTheme.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.insetField))
    }
}
