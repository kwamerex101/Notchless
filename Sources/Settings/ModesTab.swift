import SwiftUI

/// Lists dictation modes with enable/reorder/delete + add. Tapping a row opens
/// the editor (Task 7).
struct ModesTab: View {
    @ObservedObject private var store = ModeStore.shared
    @State private var editingMode: Mode?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionLabel("Modes")
            Footnote("Presets that override your dictation settings — a custom instruction, output, and formatting — chosen automatically by app or pinned from the notch menu.")

            CardGroup {
                ForEach(store.modes) { mode in
                    HStack(spacing: 10) {
                        Image(systemName: mode.systemImage).frame(width: 20).foregroundStyle(SettingsTheme.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.name).font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
                            if !mode.boundBundleIDs.isEmpty {
                                Text("^[\(mode.boundBundleIDs.count) app](inflect: true)")
                                    .font(.system(size: 10)).foregroundStyle(SettingsTheme.textTertiary)
                            }
                        }
                        Spacer()
                        if mode.id != Mode.defaultID {
                            FlatSwitch(isOn: enabledBinding(mode), label: "\(mode.name) enabled")
                        }
                        let idx = store.modes.firstIndex(of: mode) ?? 0
                        Button { store.move(from: IndexSet(integer: idx), to: idx - 1) } label: {
                            Image(systemName: "chevron.up").foregroundStyle(SettingsTheme.textSecondary)
                        }.buttonStyle(.plain).disabled(idx == 0)
                        Button { store.move(from: IndexSet(integer: idx), to: idx + 2) } label: {
                            Image(systemName: "chevron.down").foregroundStyle(SettingsTheme.textSecondary)
                        }.buttonStyle(.plain).disabled(idx >= store.modes.count - 1)
                        Button { editingMode = mode } label: {
                            Image(systemName: "pencil").foregroundStyle(SettingsTheme.textSecondary)
                        }.buttonStyle(.plain)
                        if mode.id != Mode.defaultID {
                            Button { store.delete(mode) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(SettingsTheme.textSecondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    if mode.id != store.modes.last?.id { CardDivider() }
                }
            }

            FlatButton(title: "Add Mode") {
                editingMode = Mode(name: "New Mode", systemImage: "wand.and.stars")
            }
        }
        .sheet(item: $editingMode) { mode in
            ModeEditorSheet(mode: mode)   // defined in Task 7
        }
    }

    private func enabledBinding(_ mode: Mode) -> Binding<Bool> {
        Binding(
            get: { mode.isEnabled },
            set: { var m = mode; m.isEnabled = $0; store.update(m) }
        )
    }
}
