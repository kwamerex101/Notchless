import SwiftUI

/// Passes a "request/release keyboard focus for the notch panel" callback down
/// to in-notch text fields. Defaults to a no-op so previews/DebugRender work.
private struct NotchKeyFocusKey: EnvironmentKey {
    static let defaultValue: (Bool) -> Void = { _ in }
}

extension EnvironmentValues {
    var notchKeyFocus: (Bool) -> Void {
        get { self[NotchKeyFocusKey.self] }
        set { self[NotchKeyFocusKey.self] = newValue }
    }
}

/// Debug-only: suppresses the panel's `.onDrop` file-drop target registration.
/// `ImageRenderer` renders an `onDrop`-registered view with AppKit's default
/// drag-destination highlight permanently painted in — a bright accent-colored
/// halo hugging the view's frame — instead of only while a drag is active.
/// `DebugStateDump` sets this so notch captures don't carry that artifact;
/// the real running app never sets it, so file-tray drag & drop is untouched.
private struct NotchDropTargetDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchDropTargetDisabled: Bool {
        get { self[NotchDropTargetDisabledKey.self] }
        set { self[NotchDropTargetDisabledKey.self] = newValue }
    }
}

/// Applies `.onDrop` only when `disabled` is false. Structural, not just an
/// empty file-type list — `ImageRenderer` still paints AppKit's default
/// drag-destination highlight around a view registered with `.onDrop(of: [],
/// ...)`, so the modifier itself has to be absent from the tree for the
/// debug-dump harness to get a clean capture.
private struct OptionalDropTarget: ViewModifier {
    let disabled: Bool
    let isTargeted: Binding<Bool>
    let onDrop: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        if disabled {
            content
        } else {
            content.onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in onDrop(providers) }
        }
    }
}

/// Root content hosted in the notch panel. Renders the resolved `NotchContent`
/// inside the morphing black shape, and routes hover / tap / right-click.
struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    let metrics: NotchMetrics
    var onCommand: (MediaCommand) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchDropTargetDisabled) private var dropTargetDisabled
    /// Shared namespace so album art morphs between the compact sliver and the
    /// expanded tile instead of cross-fading.
    @Namespace private var artworkNamespace

    var body: some View {
        let content = model.content
        let sizing = NotchSizing.size(for: content, metrics: metrics, dictationSettled: model.dictationSettled)
        // The tab strip lives in the notch band (in the wings beside the camera),
        // which the body already reserves — so the panel needs no extra height.
        let panelHeight = sizing.height

        let expanded = { if case .expanded = content { return true } else { return false } }()

        // A real notch resting bare covers only its own hardware cutout, but a
        // simulated one is still a black pill over fullscreen content — fade it
        // out entirely there. Hover still revives it: the mouse tracker's band
        // follows content, not visibility.
        let hiddenInFullscreen = {
            guard case .bare = content else { return false }
            return !metrics.hasRealNotch && model.fullscreenActive
                && model.settings.collapseInFullscreen
        }()

        return VStack(spacing: 0) {
            NotchShape(topCornerRadius: sizing.topRadius, bottomCornerRadius: sizing.bottomRadius)
                .fill(model.settings.notchTint.color)
                .frame(width: sizing.width, height: panelHeight)
                .background {
                    if expanded, model.settings.progressiveBlur {
                        ProgressiveBlur()
                            .frame(width: sizing.width + 24, height: panelHeight + 20)
                            .clipShape(NotchShape(topCornerRadius: sizing.topRadius + 2,
                                                  bottomCornerRadius: sizing.bottomRadius + 6))
                            .opacity(0.5)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                // Panel-level tint, drawn behind BOTH the tab strip and the
                // expanded body so they read as one surface. Black stays black;
                // a tinted view (e.g. Now Playing's album glow) carries the same
                // tint up through the strip.
                .overlay {
                    if let tint = expandedTint {
                        RadialGradient(colors: [tint.opacity(0.38), .clear],
                                       center: .topLeading, startRadius: 0, endRadius: 320)
                            .blendMode(.screen)
                            .frame(width: sizing.width, height: panelHeight)
                            .clipShape(NotchShape(topCornerRadius: sizing.topRadius,
                                                  bottomCornerRadius: sizing.bottomRadius))
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                // Flat-dark hairline — a 0.5pt stroke that follows the same
                // morphing radii as the fill, sitting beneath the content overlay.
                .overlay {
                    NotchShape(topCornerRadius: sizing.topRadius, bottomCornerRadius: sizing.bottomRadius)
                        .stroke(NotchTheme.hairline, lineWidth: NotchTheme.hairlineWidth)
                        .frame(width: sizing.width, height: panelHeight)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .top) {
                    // Content taller than the fixed `NotchSizing` height (e.g. a
                    // panel whose body doesn't fit at `panelHeight`) must anchor to
                    // the top and only overflow off the bottom — `.frame` without an
                    // explicit alignment centers the oversized content inside the
                    // clip rect, which crops the TOP (wings strip / header) instead.
                    contentView(content)
                        .frame(width: sizing.width, height: panelHeight, alignment: .top)
                        .clipShape(NotchShape(topCornerRadius: sizing.topRadius,
                                              bottomCornerRadius: sizing.bottomRadius))
                        // Key on the content's identity so a state change actually
                        // inserts/removes the view — otherwise the transition below
                        // never fires and swaps fall back to a plain crossfade.
                        .id(contentKey(content))
                        .transition(contentTransition)
                }
                // Slight magnetic growth while the hover dwell is pending.
                .scaleEffect(model.interaction == .hovering && !reduceMotion ? 1.03 : 1, anchor: .top)
                .opacity(hiddenInFullscreen ? 0 : 1)
                .animation(NotchMotion.animation(NotchMotion.morph, reduceMotion: reduceMotion),
                           value: hiddenInFullscreen)
                .contentShape(NotchShape(topCornerRadius: sizing.topRadius,
                                         bottomCornerRadius: sizing.bottomRadius))
                .onTapGesture { model.tapped() }
                .contextMenu { menu }
                .modifier(OptionalDropTarget(disabled: dropTargetDisabled,
                                             isTargeted: dropTargetBinding,
                                             onDrop: handleDrop))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // One spring drives width, height, AND the corner radii together
        // (NotchShape interpolates its radii), so the shape stretches as one
        // continuous object instead of the radii snapping.
        .animation(sizeAnimation, value: sizing)
        .environment(\.notchKeyFocus, { [weak model] want in model?.requestKeyFocus?(want) })
    }

    /// A carousel page move slides horizontally toward the new page; every other
    /// change (expand/collapse, transients) scales out of the notch. Reduce
    /// Motion collapses both to a plain fade.
    private var contentTransition: AnyTransition {
        if reduceMotion { return .opacity }
        // HUD and notifications bloom out of the notch and retract back into it.
        switch model.content {
        case .hud, .notification:
            return .move(edge: .top).combined(with: .opacity)
        default:
            break
        }
        switch model.lastMoveKind {
        case .page:
            let inEdge: Edge = model.lastMoveDirection > 0 ? .trailing : .leading
            let outEdge: Edge = model.lastMoveDirection > 0 ? .leading : .trailing
            return .asymmetric(insertion: .move(edge: inEdge).combined(with: .opacity),
                               removal: .move(edge: outEdge).combined(with: .opacity))
        case .state:
            return .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        }
    }

    /// Use the bouncy entry spring for the recording sliver→panel promote; every
    /// other size change uses the standard morph. Reduce Motion flattens both.
    private var sizeAnimation: Animation {
        if case .dictation(.recording) = model.content {
            return NotchMotion.animation(NotchMotion.dictationEnter, reduceMotion: reduceMotion)
        }
        return NotchMotion.animation(NotchMotion.morph, reduceMotion: reduceMotion)
    }

    /// Stable identity per content state so SwiftUI runs insert/remove
    /// transitions on a change (a plain view swap wouldn't animate).
    private func contentKey(_ content: NotchContent) -> String {
        switch content {
        case .bare: return "bare"
        case let .idle(a): return "idle.\(a.rawValue)"
        case .hud: return "hud"
        case let .notification(n): return "notif.\(n.id)"
        case let .expanded(a): return "expanded.\(a.rawValue)"
        case let .fileTray(expanded): return "tray.\(expanded)"
        case .mirror: return "mirror"
        case .dictation: return "dictation"
        }
    }

    @ViewBuilder
    private func contentView(_ content: NotchContent) -> some View {
        switch content {
        case .bare:
            Color.clear
        case let .idle(activity):
            IdleCompactView(activity: activity, nowPlaying: model.nowPlaying,
                            calendar: model.calendar, battery: model.battery,
                            stats: model.stats, audio: model.audio,
                            timer: model.notchTimer, privacy: model.privacy,
                            claudeStats: model.claudeStats, meetingPhase: model.meeting?.phase,
                            meetingElapsed: model.meeting?.elapsed,
                            glow: glowColor,
                            liveActivities: model.carouselActivities, metrics: metrics,
                            artworkNamespace: artworkNamespace)
        case let .hud(kind):
            HUDView(kind: kind, metrics: metrics, options: HUDOptions(from: model.settings))
        case let .notification(note):
            // Key on the note id so a replacement note re-runs the entrance
            // animation instead of reusing the previous view's `appeared` state.
            NotificationView(note: note, metrics: metrics)
                .id(note.id)
        case let .expanded(activity):
            // Tab strip lives in the wings beside the physical notch — 3 glyphs to
            // the left of the camera, battery to the right, the notch in the empty
            // middle — vertically centred in the notch band. The body keeps its own
            // notch-clearing top padding, so the strip overlays the otherwise-empty
            // band above the content (the panel sits at .statusBar level, above the
            // menu bar, so the wings render).
            ZStack(alignment: .top) {
                expandedBody(activity)
                if tabBarVisible {
                    NotchTabBar(activities: model.carouselActivities,
                                active: activity,
                                battery: model.battery,
                                onSelect: { model.select($0) },
                                notchWidth: metrics.notchWidth)
                        .padding(.top, max(2, (metrics.notchHeight - NotchTabBar.height) / 2))
                }
            }
        case let .fileTray(expanded):
            FileTrayView(store: model.fileTray, expanded: expanded, metrics: metrics)
        case .mirror:
            MirrorView(metrics: metrics, onClose: { model.showMirror = false })
        case let .dictation(phase):
            DictationView(phase: phase,
                          metrics: metrics,
                          audio: model.audio,
                          settled: model.dictationSettled,
                          startedAt: model.dictationStartedAt,
                          target: model.dictationTarget,
                          modeName: model.dictationModeName,
                          reduceMotion: reduceMotion,
                          onCancel: { model.dictationController?.cancelRecording() })
        }
    }

    @ViewBuilder
    private func expandedBody(_ activity: NotchActivity) -> some View {
        switch activity {
        case .playing, .none, .auto:
            NowPlayingExpandedView(info: model.nowPlaying, audio: model.audio,
                                   metrics: metrics, glow: glowColor, onCommand: onCommand,
                                   onActivateSource: { activateSource(model.nowPlaying?.bundleIdentifier) },
                                   artworkNamespace: artworkNamespace)
        case .calendar:
            CalendarExpandedView(snapshot: model.calendar, metrics: metrics)
        case .duo:
            DuoExpandedView(info: model.nowPlaying, snapshot: model.calendar,
                            metrics: metrics, onCommand: onCommand)
        case .dictation:
            ModeQuickPickView(metrics: metrics)
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
            ClaudeStatsExpandedView(stats: model.claudeStats, metrics: metrics, settings: model.settings)
        case .goals:
            GoalExpandedView(metrics: metrics, settings: model.settings)
        case .meeting:
            if let meeting = model.meeting {
                MeetingExpandedView(meeting: meeting, metrics: metrics)
            } else {
                Color.clear
            }
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

    /// The tint painted behind the whole expanded panel (strip + body) so they
    /// share one background. Only the media views carry the album-art glow; every
    /// other expanded view stays on the panel's black.
    private var expandedTint: Color? {
        guard case let .expanded(activity) = model.content else { return nil }
        switch activity {
        case .playing, .auto, .none, .duo: return glowColor
        default: return nil
        }
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
        Menu("Mode") {
            Button {
                ModeStore.shared.pinnedModeID = nil
            } label: {
                Label("Auto", systemImage: ModeStore.shared.pinnedModeID == nil ? "checkmark" : "sparkles")
            }
            Divider()
            ForEach(ModeStore.shared.enabledModes) { mode in
                Button {
                    ModeStore.shared.pinnedModeID = mode.id
                } label: {
                    Label(mode.name, systemImage: ModeStore.shared.pinnedModeID == mode.id ? "checkmark" : mode.systemImage)
                }
            }
        }
        Divider()
        Button("Quit Notchless") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
