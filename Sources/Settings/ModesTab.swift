import SwiftUI

/// Lists dictation modes with enable/reorder/delete + add. Tapping a row opens
/// the editor (Task 7).
struct ModesTab: View {
    @ObservedObject private var store = ModeStore.shared
    @State private var editingMode: Mode?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Modes")
            Text("Presets that override your dictation settings — a custom instruction, output, and formatting — chosen automatically by app or pinned from the notch menu.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            CardGroup {
                ForEach(store.modes) { mode in
                    HStack(spacing: 10) {
                        Image(systemName: mode.systemImage).frame(width: 20).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.name)
                            if !mode.boundBundleIDs.isEmpty {
                                Text("^[\(mode.boundBundleIDs.count) app](inflect: true)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if mode.id != Mode.defaultID {
                            Toggle("", isOn: enabledBinding(mode)).labelsHidden().toggleStyle(.switch).tint(.green)
                        }
                        Button { editingMode = mode } label: {
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                        if mode.id != Mode.defaultID {
                            Button { store.delete(mode) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    if mode.id != store.modes.last?.id { Divider() }
                }
            }

            Button {
                let new = Mode(name: "New Mode", systemImage: "wand.and.stars")
                store.add(new)
                editingMode = new
            } label: { Label("Add Mode", systemImage: "plus") }
                .buttonStyle(.link)
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
