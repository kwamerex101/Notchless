import SwiftUI

/// The hover state of the dictation notch: a horizontal switcher of modes.
/// Tapping a chip pins that mode (Auto clears the pin). Replaces the old hint.
struct ModeQuickPickView: View {
    let metrics: NotchMetrics
    @ObservedObject private var store = ModeStore.shared

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(name: "Auto", icon: "sparkles", active: store.pinnedModeID == nil, hotkey: nil) {
                    store.pinnedModeID = nil
                }
                ForEach(store.enabledModes) { mode in
                    chip(name: mode.name, icon: mode.systemImage,
                         active: store.pinnedModeID == mode.id, hotkey: mode.hotkey?.title) {
                        store.pinnedModeID = mode.id
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, metrics.notchHeight + 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func chip(name: String, icon: String, active: Bool, hotkey: String?, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12))
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let hotkey {
                    Text(hotkey).font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.15)))
                }
            }
            .foregroundStyle(active ? Color.black : .white.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active ? Color.white : Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }
}
