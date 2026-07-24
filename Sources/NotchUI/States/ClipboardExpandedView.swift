import SwiftUI

/// The expanded clipboard panel: recent copies (click to re-copy) plus a
/// screen colour picker.
struct ClipboardExpandedView: View {
    @ObservedObject private var store = ClipboardStore.shared
    let metrics: NotchMetrics

    // Which row just got re-copied, so it can flash "Copied" for 900ms (flat-dark
    // spec §4) before fading back to its plain label.
    @State private var copiedID: ClipboardStore.Item.ID?
    @State private var copiedFadeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clipboard").notchSectionHeader()
                Spacer()
                Button { store.pickColor() } label: {
                    Label("Pick colour", systemImage: "eyedropper")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.textBrightSecondary)
                }.buttonStyle(.plain)
                if !store.items.isEmpty {
                    Button { store.clear() } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(NotchTheme.textSecondary)
                    }.buttonStyle(.plain)
                }
            }

            if store.items.isEmpty {
                Text("Copied text appears here.")
                    .font(.system(size: 12)).foregroundStyle(NotchTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.items.prefix(8)) { item in row(item) }
                    }
                }
            }
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ item: ClipboardStore.Item) -> some View {
        Button {
            store.copy(item)
            flashCopied(item.id)
        } label: {
            HStack(spacing: 8) {
                if let color = ClipboardColorParser.color(for: item.text) {
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
                }
                Text(item.text)
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if copiedID == item.id {
                    Label("Copied", systemImage: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.positive)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: NotchDesign.chipRadius).fill(NotchTheme.inset))
        }.buttonStyle(.plain)
    }

    /// Flashes the green "Copied" check for 900ms, then fades it out (flat-dark spec §4).
    private func flashCopied(_ id: ClipboardStore.Item.ID) {
        copiedFadeTask?.cancel()
        withAnimation(NotchMotion.quick) { copiedID = id }
        copiedFadeTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(NotchMotion.quick) { copiedID = nil } }
        }
    }
}

/// Recognises a bare hex colour ("#RRGGBB") so its row can show a swatch —
/// clipboard entries have no dedicated colour type, only text.
private enum ClipboardColorParser {
    static func color(for text: String) -> Color? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(hex: value)
    }
}

/// Small live count badge for the compact clipboard cue.
struct ClipboardBadge: View {
    @ObservedObject private var store = ClipboardStore.shared
    var body: some View {
        Text("\(store.items.count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
    }
}
