import SwiftUI
import AppKit

/// Edits one mode: name, icon, instruction, per-field overrides (each with an
/// "override vs inherit" toggle), and app bindings. Saves to ModeStore on Done.
struct ModeEditorSheet: View {
    @State var mode: Mode
    @Environment(\.dismiss) private var dismiss
    private var store: ModeStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode.isBuiltIn ? "Edit \(mode.name)" : "Edit Mode").font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Identity
                    HStack {
                        TextField("Name", text: $mode.name).textFieldStyle(.roundedBorder)
                        IconPicker(selection: $mode.systemImage)
                    }

                    Text("INSTRUCTION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextEditor(text: instructionBinding)
                        .font(.body).frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    Text("Added to the cleanup prompt for this mode. Leave empty to inherit.")
                        .font(.caption2).foregroundStyle(.secondary)

                    // Overrides
                    OverrideRow("Output", isSet: mode.output != nil, onToggle: { mode.output = $0 ? .pasteActiveApp : nil }) {
                        Picker("", selection: Binding(get: { mode.output ?? .pasteActiveApp }, set: { mode.output = $0 })) {
                            ForEach(DictationOutput.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden()
                    }
                    OverrideRow("Cleanup", isSet: mode.cleanup != nil, onToggle: { mode.cleanup = $0 ? .smart : nil; if !$0 { mode.cleanupIntensity = nil } }) {
                        HStack {
                            Picker("", selection: Binding(get: { mode.cleanup ?? .smart }, set: { mode.cleanup = $0 })) {
                                ForEach(DictationCleanup.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                            Picker("", selection: Binding(get: { mode.cleanupIntensity ?? .light }, set: { mode.cleanupIntensity = $0 })) {
                                ForEach(DictationCleanupIntensity.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden()
                        }
                    }
                    OverrideRow("Engine", isSet: mode.engine != nil, onToggle: { mode.engine = $0 ? .appleSpeech : nil }) {
                        Picker("", selection: Binding(get: { mode.engine ?? .appleSpeech }, set: { mode.engine = $0 })) {
                            ForEach(DictationEngine.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden()
                    }
                    OverrideToggleRow("Voice commands", value: $mode.voiceCommands)
                    OverrideToggleRow("Smart formatting", value: $mode.smartFormatting)
                    OverrideToggleRow("Auto-capitalize", value: $mode.autoCapitalize)

                    // App binding
                    Text("AUTO-SELECT FOR APPS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(mode.boundBundleIDs, id: \.self) { bid in
                        HStack {
                            Text(appName(bid)).font(.callout)
                            Spacer()
                            Button { mode.boundBundleIDs.removeAll { $0 == bid } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    Menu("Add app…") {
                        ForEach(runningApps(), id: \.bundleID) { app in
                            Button(app.name) {
                                if !mode.boundBundleIDs.contains(app.bundleID) { mode.boundBundleIDs.append(app.bundleID) }
                            }
                        }
                    }.frame(width: 160)
                }
                .padding(.vertical, 4)
            }.frame(width: 420, height: 380)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Done") { store.update(mode); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var instructionBinding: Binding<String> {
        Binding(get: { mode.instruction ?? "" }, set: { mode.instruction = $0.isEmpty ? nil : $0 })
    }

    private func appName(_ bundleID: String) -> String {
        runningApps().first { $0.bundleID == bundleID }?.name ?? bundleID
    }
    private func runningApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .sorted { $0.0 < $1.0 }
    }
}

/// An override row with an "override vs inherit" toggle that reveals `content`.
private struct OverrideRow<Content: View>: View {
    let title: String
    let isSet: Bool
    let onToggle: (Bool) -> Void
    @ViewBuilder let content: Content
    init(_ title: String, isSet: Bool, onToggle: @escaping (Bool) -> Void, @ViewBuilder content: () -> Content) {
        self.title = title; self.isSet = isSet; self.onToggle = onToggle; self.content = content()
    }
    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { isSet }, set: onToggle)) { Text(title) }
                .toggleStyle(.checkbox)
            Spacer()
            if isSet { content }
        }
    }
}

/// A tri-state override for a Bool field (inherit / on / off).
private struct OverrideToggleRow: View {
    let title: String
    @Binding var value: Bool?
    init(_ title: String, value: Binding<Bool?>) { self.title = title; self._value = value }
    var body: some View {
        HStack {
            Toggle(isOn: Binding(get: { value != nil }, set: { value = $0 ? true : nil })) { Text(title) }
                .toggleStyle(.checkbox)
            Spacer()
            if value != nil {
                Toggle("", isOn: Binding(get: { value ?? false }, set: { value = $0 })).labelsHidden().toggleStyle(.switch).tint(.green)
            }
        }
    }
}

/// A tiny SF-symbol picker from a curated list.
private struct IconPicker: View {
    @Binding var selection: String
    private let icons = ["mic", "envelope", "chevron.left.forwardslash.chevron.right", "note.text",
                         "bubble.left", "wand.and.stars", "briefcase", "terminal", "text.book.closed", "message"]
    var body: some View {
        Menu {
            ForEach(icons, id: \.self) { icon in
                Button { selection = icon } label: { Label(icon, systemImage: icon) }
            }
        } label: { Image(systemName: selection).frame(width: 24) }
        .frame(width: 44)
    }
}
