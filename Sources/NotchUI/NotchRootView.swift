import SwiftUI

/// Root content hosted in the notch panel. Renders the resolved `NotchContent`
/// inside the morphing black shape, and routes hover / tap / right-click.
struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    let metrics: NotchMetrics
    var onCommand: (MediaCommand) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    var body: some View {
        let content = model.content
        let sizing = NotchSizing.size(for: content, metrics: metrics)
        let barExtra = tabBarVisible ? NotchTabBar.height : 0
        let panelHeight = sizing.height + barExtra

        let expanded = { if case .expanded = content { return true } else { return false } }()

        return VStack(spacing: 0) {
            NotchShape(topCornerRadius: sizing.topRadius, bottomCornerRadius: sizing.bottomRadius)
                .fill(Color.black)
                .frame(width: sizing.width, height: panelHeight)
                .background {
                    if expanded, model.settings.progressiveBlur {
                        ProgressiveBlur()
                            .frame(width: sizing.width + 24, height: sizing.height + 20)
                            .clipShape(RoundedRectangle(cornerRadius: sizing.bottomRadius + 6, style: .continuous))
                            .opacity(0.5)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    contentView(content)
                        .frame(width: sizing.width, height: panelHeight)
                        .clipShape(NotchShape(topCornerRadius: sizing.topRadius,
                                              bottomCornerRadius: sizing.bottomRadius))
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
                .contentShape(NotchShape(topCornerRadius: sizing.topRadius,
                                         bottomCornerRadius: sizing.bottomRadius))
                .onTapGesture { model.tapped() }
                .contextMenu { menu }
                .onDrop(of: [.fileURL], isTargeted: dropTargetBinding) { providers in
                    handleDrop(providers)
                }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchViewModel.morph, value: sizing.width)
        .animation(NotchViewModel.morph, value: panelHeight)
    }

    @ViewBuilder
    private func contentView(_ content: NotchContent) -> some View {
        switch content {
        case .bare:
            Color.clear
        case let .idle(activity):
            IdleCompactView(activity: activity, nowPlaying: model.nowPlaying,
                            calendar: model.calendar, battery: model.battery,
                            stats: model.stats, musicSpectrum: model.musicSpectrum,
                            timer: model.notchTimer, privacy: model.privacy,
                            claudeStats: model.claudeStats, glow: glowColor,
                            liveActivities: model.carouselActivities, metrics: metrics)
        case let .hud(kind):
            HUDView(kind: kind, metrics: metrics)
        case let .notification(note):
            NotificationView(note: note, metrics: metrics)
        case let .expanded(activity):
            if tabBarVisible {
                VStack(spacing: 0) {
                    NotchTabBar(activities: model.carouselActivities,
                                active: activity,
                                battery: model.battery,
                                metrics: metrics,
                                onSelect: { model.select($0) })
                    expandedBody(activity)
                }
            } else {
                expandedBody(activity)
            }
        case let .fileTray(expanded):
            FileTrayView(store: model.fileTray, expanded: expanded, metrics: metrics)
        case .mirror:
            MirrorView(metrics: metrics, onClose: { model.showMirror = false })
        case let .dictation(phase):
            DictationView(phase: phase, metrics: metrics, level: model.dictationLevel, spectrum: model.dictationSpectrum)
        }
    }

    @ViewBuilder
    private func expandedBody(_ activity: NotchActivity) -> some View {
        switch activity {
        case .playing, .none, .auto:
            NowPlayingExpandedView(info: model.nowPlaying, musicSpectrum: model.musicSpectrum,
                                   metrics: metrics, glow: glowColor, onCommand: onCommand,
                                   onActivateSource: { activateSource(model.nowPlaying?.bundleIdentifier) })
        case .calendar:
            CalendarExpandedView(snapshot: model.calendar, metrics: metrics)
        case .duo:
            DuoExpandedView(info: model.nowPlaying, snapshot: model.calendar,
                            metrics: metrics, onCommand: onCommand)
        case .dictation:
            DictationHintView(metrics: metrics)
        case .battery:
            BatteryExpandedView(battery: model.battery, metrics: metrics)
        case .stats:
            StatsExpandedView(stats: model.stats, metrics: metrics)
        case .timer:
            TimerExpandedView(timer: model.notchTimer, metrics: metrics)
        case .clipboard:
            ClipboardExpandedView(metrics: metrics)
        case .todos:
            TodoExpandedView(metrics: metrics)
        case .privacy:
            PrivacyExpandedView(privacy: model.privacy, metrics: metrics)
        case .claudeUsage:
            ClaudeStatsExpandedView(stats: model.claudeStats, metrics: metrics)
        }
    }

    /// The strip shows only in the expanded state, when enabled, and only if
    /// there is more than one page to move between.
    private var tabBarVisible: Bool {
        guard case .expanded = model.content else { return false }
        return model.settings.showTabBar && model.carouselActivities.count >= 2
    }

    private var glowColor: Color? {
        model.settings.albumArtGlow ? model.artworkColor : nil
    }

    /// Brings the app that's currently playing (Music, Spotify, a browser tab
    /// host, …) to the front. See PLAN.md — Alcove's "focus playing tab".
    private func activateSource(_ bundleID: String?) {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private var dropTargetBinding: Binding<Bool> {
        Binding(get: { model.isDropTargeted }, set: { model.isDropTargeted = $0 })
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard model.settings.fileTrayEnabled else { return false }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.fileTray.add([url]) }
            }
        }
        return true
    }

    @ViewBuilder
    private var menu: some View {
        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")")
        Button(model.showMirror ? "Hide Camera Mirror" : "Camera Mirror") { model.toggleMirror() }
        Button("Settings…") { onOpenSettings() }.keyboardShortcut(",")
        Divider()
        Button("Quit Notchless") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
