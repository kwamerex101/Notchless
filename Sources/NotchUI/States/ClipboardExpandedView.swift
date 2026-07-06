import SwiftUI

/// The expanded clipboard panel: recent copies (click to re-copy) plus a
/// screen colour picker.
struct ClipboardExpandedView: View {
    @ObservedObject private var store = ClipboardStore.shared
    let metrics: NotchMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clipboard").notchSectionHeader()
                Spacer()
                Button { store.pickColor() } label: {
                    Label("Pick colour", systemImage: "eyedropper")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
                if !store.items.isEmpty {
                    Button { store.clear() } label: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }.buttonStyle(.plain)
                }
            }

            if store.items.isEmpty {
                Text("Copied text appears here.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.items.prefix(8)) { item in
                            Button { store.copy(item) } label: {
                                Text(item.text)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
