import SwiftUI
import UniformTypeIdentifiers

/// File Tray content: a row of draggable file chips when expanded, or a compact
/// count pill when idle. Files can be dragged back out to Finder/apps.
struct FileTrayView: View {
    @ObservedObject var store: FileTrayStore
    let expanded: Bool
    let metrics: NotchMetrics

    var body: some View {
        if expanded {
            expandedTray
        } else {
            compactPill
        }
    }

    private var expandedTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("File Tray", systemImage: "tray.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if !store.isEmpty {
                    Button { store.clear() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.5))
                    }.buttonStyle(.plain)
                }
            }
            if store.isEmpty {
                Text("Drop files here")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.items, id: \.self) { url in
                            chip(url)
                        }
                    }
                }
            }
        }
        .padding(.top, metrics.notchHeight + 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func chip(_ url: URL) -> some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 34, height: 34)
            Text(url.lastPathComponent)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            ShareLink(item: url) { Label("Share… (AirDrop)", systemImage: "square.and.arrow.up") }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove", role: .destructive) { store.remove(url) }
        }
    }

    private var compactPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)
            Text("\(store.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
