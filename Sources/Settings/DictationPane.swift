import SwiftUI
import Speech
import AVFoundation

struct DictationPane: View {
    @ObservedObject var settings = DictationSettings.shared
    @ObservedObject var dictionary = DictationDictionary.shared
    @ObservedObject var history = DictationHistory.shared
    @ObservedObject var snippets = DictationSnippets.shared
    @ObservedObject var parakeet = ParakeetModelStore.shared
    @ObservedObject var styles = StyleStore.shared

    @State private var newTerm = ""
    @State private var newTrigger = ""
    @State private var newExpansion = ""
    @State private var editingRecord: DictationRecord?
    @State private var editingText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(section: .dictation)

            SectionLabel("General")
            CardGroup {
                ToggleRow(title: "Enable dictation", isOn: $settings.enabled)
                Divider()
                HStack {
                    Text("Hotkey (hold to talk)")
                    Spacer()
                    Picker("", selection: $settings.hotkey) {
                        ForEach(DictationHotkeyOption.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 190)
                }
                Divider()
                HStack {
                    Text("Language")
                    Spacer()
                    Picker("", selection: $settings.languageID) {
                        ForEach(languages, id: \.id) { Text($0.name).tag($0.id) }
                    }.labelsHidden().frame(width: 190)
                }
                Divider()
                HStack {
                    Text("Microphone")
                    Spacer()
                    Picker("", selection: $settings.microphoneUID) {
                        Text("System default").tag("")
                        ForEach(microphones, id: \.uid) { Text($0.name).tag($0.uid) }
                    }.labelsHidden().frame(width: 190)
                }
                Divider()
                HStack {
                    Text("Max recording length")
                    Spacer()
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
                HStack {
                    Text("Engine")
                    Spacer()
                    Picker("", selection: $settings.engine) {
                        ForEach(DictationEngine.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 220)
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
                HStack {
                    Text("Polish transcript")
                    Spacer()
                    Picker("", selection: $settings.cleanup) {
                        ForEach(DictationCleanup.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 150)
                }
                Text("Smart cleans only longer transcripts that look like they need it; the raw text always stands if cleanup fails or times out.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if settings.cleanup != .off {
                    Divider()
                    HStack {
                        Text("Backend")
                        Spacer()
                        Picker("", selection: $settings.cleanupBackend) {
                            ForEach(DictationCleanupBackend.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 190)
                    }
                    Divider()
                    HStack {
                        Text("Intensity")
                        Spacer()
                        Picker("", selection: $settings.cleanupIntensity) {
                            ForEach(DictationCleanupIntensity.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 190)
                    }
                    Divider()
                    HStack {
                        Text("Timeout")
                        Spacer()
                        Slider(value: Binding(
                            get: { Double(settings.cleanupTimeoutSeconds) },
                            set: { settings.cleanupTimeoutSeconds = Int($0) }
                        ), in: 5...60, step: 5).frame(width: 150)
                        Text("\(settings.cleanupTimeoutSeconds)s").frame(width: 40, alignment: .trailing)
                    }
                    if settings.cleanupBackend == .api || settings.cleanupBackend == .auto {
                        Divider()
                        HStack {
                            Text("Anthropic API key")
                            Spacer()
                            SecureField("sk-ant-…", text: apiKeyBinding)
                                .textFieldStyle(.roundedBorder).frame(width: 220)
                        }
                        Text("Stored in your Keychain. Used by the API and Automatic backends; Automatic falls back to the Claude CLI when empty.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if settings.cleanupBackend == .onDevice {
                        Divider()
                        Text("On-device Gemma runs locally with no network. Download the model in the Models section below.")
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

            SectionLabel("Personalization")
            CardGroup {
                HStack {
                    Text("Your name")
                    Spacer()
                    TextField("Optional", text: $settings.userName)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                }
                Text("Used for a friendly greeting on the dictation cue.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                ToggleRow(title: "Context-aware cleanup", isOn: $settings.contextAwareCleanup)
                Text("Tailors cleanup to the app you're dictating into — preserves code in editors, stays casual in chat — and learns each app's tone over time.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if settings.contextAwareCleanup && !styles.styles.isEmpty {
                SectionLabel("Per-app style")
                CardGroup {
                    ForEach(Array(styles.styles.values.sorted { $0.sampleCount > $1.sampleCount })) { style in
                        StyleRow(style: style)
                        if style.id != styles.styles.values.sorted(by: { $0.sampleCount > $1.sampleCount }).last?.id {
                            Divider()
                        }
                    }
                }
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

            SectionLabel("History")
            CardGroup {
                HStack {
                    Text("Keep for")
                    Spacer()
                    Stepper("\(settings.historyRetentionDays) days", value: $settings.historyRetentionDays, in: 1...365)
                        .fixedSize()
                }
                Divider()
                ToggleRow(title: "Encrypt history at rest", isOn: $settings.encryptHistory)
                if history.records.isEmpty {
                    Divider()
                    Text("No dictations yet.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Divider()
                    ForEach(history.records.prefix(6)) { record in
                        HStack {
                            Text(record.text).lineLimit(1)
                            Spacer()
                            Button { beginEditing(record) } label: {
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                            Button { history.remove(record) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("Edit a dictation to fix a word — correct the same word three times and it's added to your custom words automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Clear history", role: .destructive) { history.clear() }
                        .buttonStyle(.link)
                }
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

    private func beginEditing(_ record: DictationRecord) {
        editingText = record.text
        editingRecord = record
    }

    /// The Anthropic key lives in the Keychain, so bridge it through a manual
    /// binding rather than `$settings.…`.
    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { settings.anthropicAPIKey },
            set: { settings.anthropicAPIKey = $0 }
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

    private var microphones: [(uid: String, name: String)] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio, position: .unspecified
        ).devices.map { ($0.uniqueID, $0.localizedName) }
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
                Picker("", selection: Binding(
                    get: { style.acceptedTone ?? .none },
                    set: { store.accept(style.bundleID, tone: $0) }
                )) {
                    ForEach(StyleTone.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 130)
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
