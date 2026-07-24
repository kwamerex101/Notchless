import AppKit
import SwiftUI
import Combine

/// Owns all notch state and resolves it into a single `NotchContent` for the
/// view, applying priority: HUD > notification > expanded > idle > bare.
@MainActor
final class NotchViewModel: ObservableObject {
    // Interaction
    @Published var interaction: Interaction = .collapsed

    /// True while the active Space (on the notch's screen) is a fullscreen app.
    /// Set by EffectsController; drives the collapse-to-bare-in-fullscreen rest.
    @Published var fullscreenActive = false

    /// Set by FullscreenRevealController; true while the notch is revealed
    /// over a fullscreen app. Suppresses the bare-rest override below so the
    /// resting activity is what actually appears while revealed.
    @Published var revealActive = false

    // Transient / top priority
    @Published var hud: HUDKind?
    @Published var notification: TransientNotification?

    // Content providers
    @Published var nowPlaying: NowPlayingInfo?
    @Published var calendar: CalendarSnapshot?
    @Published var battery: BatteryInfo?
    @Published var stats: SystemStats?
    @Published var notchTimer: NotchTimerInfo?
    @Published var privacy: PrivacyStatus?
    @Published var claudeStats: ClaudeUsageStats?
    /// The activity the user cycled to in the Auto carousel (nil = default top).
    @Published private var manualActivity: NotchActivity?
    /// High-frequency audio levels live here, off the god model, so the ~30 Hz
    /// visualizer stream only invalidates the visualizer subtree.
    let audio = AudioLevelsModel()
    /// Vibrant color sampled from the current artwork (album-art glow).
    @Published var artworkColor: Color?

    // File Tray
    let fileTray = FileTrayStore()
    @Published var isDropTargeted = false

    // Goals
    let goals = GoalStore.shared

    // Todos
    let todos = TodoStore.shared
    private var todosObserver: AnyCancellable?

    // Camera mirror
    @Published var showMirror = false

    /// Set by AppDelegate to let in-notch text fields (Tasks quick-add, Goals
    /// quick-log) request/release keyboard focus for the panel. `true` when a
    /// field starts editing, `false` when it ends.
    var requestKeyFocus: ((Bool) -> Void)?

    // Meeting capture (set by AppDelegate once the controller is built). Forward
    // the controller's own @Published changes (phase/elapsed) so the notch's
    // resolved content and compact cue re-render as a capture progresses.
    @Published var meeting: MeetingController? {
        didSet {
            meetingObserver = meeting?.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
    private var meetingObserver: AnyCancellable?

    // Dictation (ListenToMe)
    @Published var dictation: DictationPhase?
    /// The recording panel has grown past its entry sliver. Drives sliver↔panel
    /// sizing and reveals the transcript + control row.
    @Published var dictationSettled: Bool = true
    /// When the current recording began — drives the elapsed timer view-locally.
    @Published var dictationStartedAt: Date?
    /// Where dictated text will land (frontmost app at record start).
    @Published var dictationTarget: DictationTarget?
    /// The active dictation mode's name (nil / "Default" → not shown as a chip).
    @Published var dictationModeName: String?
    private var dictationSettleWork: DispatchWorkItem?
    let dictationSettings = DictationSettings.shared
    let dictationDictionary = DictationDictionary.shared
    let dictationHistory = DictationHistory.shared
    private var dictationDismiss: DispatchWorkItem?
    /// Set by AppDelegate after the controller is created, so in-notch buttons
    /// (e.g. the recording cancel) can drive a session. Weak to avoid a cycle.
    weak var dictationController: DictationController?

    let settings: SettingsStore

    private var hudDismiss: DispatchWorkItem?
    private var notifDismiss: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var hoverIntentWork: DispatchWorkItem?
    private var goalObserver: AnyCancellable?

    // Thin aliases onto the shared motion vocabulary (NotchMotion).
    static let morph = NotchMotion.morph
    static let quickMorph = NotchMotion.quick

    init(settings: SettingsStore? = nil) {
        self.settings = settings ?? .shared
        goalObserver = goals.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        todosObserver = todos.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Resolved presentation

    /// Debug-only: forces `content` for the `--dump-states` render harness.
    @Published var debugContentOverride: NotchContent?

    /// The single content the notch should render right now.
    var content: NotchContent {
        if let debugContentOverride { return debugContentOverride }
        if let hud { return .hud(hud) }
        if let dictation { return .dictation(dictation) }
        if let notification { return .notification(notification) }
        if showMirror { return .mirror }
        if settings.fileTrayEnabled, isDropTargeted { return .fileTray(expanded: true) }
        if interaction == .expanded { return .expanded(activeExpandedActivity) }

        // In fullscreen the menu bar is gone and window content reaches the top
        // edge, so resting wings would sit on top of it. Rest bare — the physical
        // cutout covers nothing — until the user hovers; transients above still show.
        // Suppressed while revealed: the edge-reveal hover would otherwise fade in
        // a panel with nothing in it.
        if settings.collapseInFullscreen, fullscreenActive, interaction == .collapsed, !revealActive {
            return .bare
        }

        if settings.fileTrayEnabled, !fileTray.isEmpty {
            return .fileTray(expanded: interaction == .hovering)
        }

        if let activity = resolvedIdleActivity(hovering: interaction == .hovering) {
            return .idle(activity)
        }
        return .bare
    }

    /// True when a system-stats readout is actually on screen (the idle cue or
    /// the expanded page). Lets `StatsController` sample at the user's interval
    /// only when it matters and idle-sample slowly otherwise.
    var statsVisible: Bool {
        switch content {
        case .idle(.stats), .expanded(.stats): return true
        default: return false
        }
    }

    /// True when the now-playing music visualizer is actually on screen, so the
    /// system-audio tap only needs to run then (it still also requires playback
    /// and the setting). The dictation waveform is fed separately and isn't
    /// gated by this.
    var visualizerOnScreen: Bool {
        switch content {
        case .idle(.playing), .idle(.auto), .idle(.none), .idle(.duo),
             .expanded(.playing), .expanded(.auto), .expanded(.none), .expanded(.duo):
            return true
        default:
            return false
        }
    }

    /// Every Live Activity that's currently live, in priority order. In Auto
    /// mode the user can cycle through these (e.g. media vs. the mic dot on a
    /// call); the first is the default shown.
    var liveActivities: [NotchActivity] {
        var result: [NotchActivity] = []
        if privacy?.isActive ?? false { result.append(.privacy) }
        if notchTimer?.isActive ?? false { result.append(.timer) }
        if nowPlaying != nil { result.append(.playing) }
        if settings.todosEnabled, !todos.isEmpty { result.append(.todos) }
        if settings.goalsEnabled, goals.hasActiveGoals { result.append(.goals) }
        if let battery, battery.isPluggedIn || battery.isCharging { result.append(.battery) }
        // Surface the meeting page whenever the controller exists AND the user has
        // enabled meeting capture (Settings > Meetings); a capture in progress
        // jumps it to the front.
        if let meeting, UserDefaults.standard.bool(forKey: "meeting.enabled") {
            if meeting.phase == .idle { result.append(.meeting) }
            else { result.insert(.meeting, at: 0) }
        }
        return result
    }

    /// Everything the user can swipe through: the live activities (incl. Goals
    /// when enabled) plus the info pages — Calendar always, System Stats and
    /// Claude Usage only when their toggles are on.
    var carouselActivities: [NotchActivity] {
        var result = liveActivities
        var pages: [NotchActivity] = [.calendar]
        if settings.statsEnabled { pages.append(.stats) }
        if settings.claudeUsageEnabled { pages.append(.claudeUsage) }
        for page in pages where !result.contains(page) {
            result.append(page)
        }
        return result
    }

    /// The concrete activity to rest in the notch at idle, or nil for a bare
    /// notch. In Auto mode this is whatever Live Activity is currently live —
    /// or the one the user cycled to.
    private func resolvedIdleActivity(hovering: Bool) -> NotchActivity? {
        switch settings.idleActivity {
        case .auto:
            return autoCarouselActivity()
        case .none:
            // The privacy dot still shows, like macOS's own indicator.
            return (privacy?.isActive ?? false) ? .privacy : nil
        default:
            if privacy?.isActive ?? false { return .privacy }
            let idle = settings.idleActivity
            if hovering { return idle }
            return hasIdleContent(idle) ? idle : nil
        }
    }

    /// The current activity in the Auto carousel: the user's manual pick if it's
    /// still live, else the top-priority live one.
    private func autoCarouselActivity() -> NotchActivity? {
        guard !liveActivities.isEmpty else { return nil }   // bare when nothing live
        if let manual = manualActivity, carouselActivities.contains(manual) { return manual }
        return liveActivities.first
    }

    /// Advances the carousel to the next page (horizontal swipe) — through the
    /// live activities and the calendar/stats/claude pages. Works in every idle
    /// mode as long as there's more than one page to move between.
    func cycleLiveActivity() {
        let carousel = carouselActivities
        guard carousel.count >= 2 else { return }
        let current = (manualActivity.flatMap { carousel.contains($0) ? $0 : nil })
            ?? liveActivities.first ?? carousel[0]
        let index = carousel.firstIndex(of: current) ?? 0
        // Same motion + haptic as a tab tap, so a swipe animates identically
        // instead of jump-cutting.
        lastMoveDirection = 1
        lastMoveKind = .page
        withAnimation(Self.morph) { manualActivity = carousel[(index + 1) % carousel.count] }
        if settings.hapticFeedback { HapticService.tap() }
    }

    /// Direction of the most recent carousel move (+1 forward, -1 back), so the
    /// view can slide page content the right way. Read by NotchRootView.
    private(set) var lastMoveDirection = 1

    /// Whether the last content change was a carousel page move (slide) or a
    /// state change like expand/collapse (scale from the notch).
    enum MoveKind { case state, page }
    private(set) var lastMoveKind: MoveKind = .state

    /// Jumps the carousel straight to `activity` (a tab tap). Mirrors what a
    /// swipe does for one step: sets the manual pick and gives haptic feedback.
    /// Ignored if `activity` isn't a current carousel page. Unlike
    /// `cycleLiveActivity()`, this intentionally has no `liveActivities`
    /// emptiness guard — the info pages (calendar/stats/claudeUsage) are
    /// tappable even when nothing is live.
    func select(_ activity: NotchActivity) {
        guard carouselActivities.contains(activity) else { return }
        // Slide toward the tapped page: derive direction from the index delta.
        let carousel = carouselActivities
        if let from = (manualActivity ?? liveActivities.first).flatMap({ carousel.firstIndex(of: $0) }),
           let to = carousel.firstIndex(of: activity) {
            lastMoveDirection = to >= from ? 1 : -1
        }
        lastMoveKind = .page
        withAnimation(Self.morph) { manualActivity = activity }
        if settings.hapticFeedback { HapticService.tap() }
    }

    /// Which activity a click/hover expands into. An explicit pick — a tab tap
    /// or a swipe — wins in every mode as long as it's still a valid carousel
    /// page; otherwise we fall back to the mode's default resting activity.
    var activeExpandedActivity: NotchActivity {
        if let manual = manualActivity, carouselActivities.contains(manual) { return manual }
        switch settings.idleActivity {
        case .auto:
            return autoCarouselActivity() ?? (nowPlaying != nil ? .playing : .calendar)
        case .none:
            if privacy?.isActive ?? false { return .privacy }
            return nowPlaying != nil ? .playing : .calendar
        default:
            if privacy?.isActive ?? false { return .privacy }
            return settings.idleActivity
        }
    }

    private func hasIdleContent(_ activity: NotchActivity) -> Bool {
        switch activity {
        case .none: return false
        case .auto: return !liveActivities.isEmpty
        case .playing: return nowPlaying != nil
        case .calendar: return true
        case .duo: return nowPlaying != nil || (calendar?.hasEvents ?? false) || settings.forceEnableActivity
        case .dictation: return true  // the mic-ready cue always rests in the notch
        case .battery: return battery != nil
        case .stats: return settings.statsEnabled && stats != nil
        case .timer: return true  // always rests so it can be started from the notch
        case .clipboard: return true
        case .todos: return settings.todosEnabled && !todos.isEmpty
        case .privacy: return privacy?.isActive ?? false
        case .claudeUsage: return settings.claudeUsageEnabled && claudeStats != nil
        case .goals: return settings.goalsEnabled && goals.hasActiveGoals
        case .meeting: return meeting != nil && UserDefaults.standard.bool(forKey: "meeting.enabled")
        }
    }

    // MARK: - Interaction

    func hoverChanged(_ hovering: Bool) {
        collapseWork?.cancel()
        hoverIntentWork?.cancel()
        lastMoveKind = .state
        if hovering {
            guard interaction != .expanded else { return }
            // Acknowledge the hover instantly with a slight magnetic growth, but
            // wait out a short dwell before fully expanding, so a mouse-past
            // across the notch doesn't detonate the whole panel.
            withAnimation(NotchMotion.micro) { interaction = .hovering }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.settings.hapticFeedback { HapticService.tap() }
                withAnimation(Self.morph) { self.interaction = .expanded }
            }
            hoverIntentWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.hoverDwell, execute: work)
        } else {
            // Grace delay before collapsing so brief exits don't flicker.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lastMoveKind = .state
                withAnimation(Self.morph) {
                    self.interaction = .collapsed
                    if self.settings.idleActivity != .auto { self.manualActivity = nil }
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.collapseGrace, execute: work)
        }
    }

    func toggleMirror() {
        lastMoveKind = .state
        withAnimation(Self.morph) { showMirror.toggle() }
    }

    /// Drives the dictation notch activity. Terminal phases (success/error)
    /// auto-dismiss after a beat; pass nil to clear immediately.
    func setDictation(_ phase: DictationPhase?) {
        dictationDismiss?.cancel()
        dictationSettleWork?.cancel()
        lastMoveKind = .state

        if case .recording = phase {
            dictationStartedAt = Date()
            // Skip the sliver beat when it would read as a shrink (already
            // expanded) or when Reduce Motion is on (two size steps flicker).
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let skipSliver = reduceMotion || interaction == .expanded
            withAnimation(Self.quickMorph) {
                dictationSettled = skipSliver
                dictation = phase
            }
            if !skipSliver {
                let work = DispatchWorkItem { [weak self] in
                    withAnimation(NotchMotion.dictationEnter) { self?.dictationSettled = true }
                }
                dictationSettleWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
            }
        } else {
            withAnimation(Self.quickMorph) { dictation = phase }
        }

        if phase == nil {
            dictationStartedAt = nil
            dictationTarget = nil
            dictationModeName = nil
        }

        if let phase, !phase.isActive {
            // Errors dwell a little longer so they can be read.
            let dwell: TimeInterval = {
                if case .error = phase { return NotchMotion.dictationDismiss + 1.2 }
                return NotchMotion.dictationDismiss
            }()
            let work = DispatchWorkItem { [weak self] in
                withAnimation(Self.morph) { self?.dictation = nil }
            }
            dictationDismiss = work
            DispatchQueue.main.asyncAfter(deadline: .now() + dwell, execute: work)
        }
    }

    /// A click keeps the notch open (buttons handle their own taps); it never
    /// collapses, so clicking inside the expanded panel is safe.
    func tapped() {
        lastMoveKind = .state
        withAnimation(Self.morph) { interaction = .expanded }
    }

    func collapse() {
        collapseWork?.cancel()
        lastMoveKind = .state
        withAnimation(Self.morph) {
            interaction = .collapsed
            if settings.idleActivity != .auto { manualActivity = nil }
        }
    }

    // MARK: - HUD

    func showHUD(_ kind: HUDKind) {
        hudDismiss?.cancel()
        lastMoveKind = .state
        withAnimation(Self.quickMorph) { hud = kind }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.morph) { self?.hud = nil }
        }
        hudDismiss = work
        let delay = Self.clampHUDDelay(settings.hudHideDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Clamps a raw `hudHideDelay` setting into the supported 0.5...5s range.
    /// Pure so it can be unit-tested without a live `NotchViewModel`.
    nonisolated static func clampHUDDelay(_ raw: Double) -> Double {
        min(5.0, max(0.5, raw))
    }

    /// Clears the notch HUD safely — cancels any pending auto-dismiss so it
    /// can't fire after `hud` has already been cleared, and reuses `showHUD`'s
    /// dismiss animation. Used by `HUDPresenter` to guarantee no double-present
    /// when routing to the floating panel, and when switching routes.
    func hideHUD() {
        hudDismiss?.cancel()
        hudDismiss = nil
        withAnimation(Self.morph) { hud = nil }
    }

    // MARK: - Notifications

    func show(_ note: TransientNotification) {
        notifDismiss?.cancel()
        lastMoveKind = .state
        withAnimation(Self.quickMorph) { notification = note }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.morph) { self?.notification = nil }
        }
        notifDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + note.duration, execute: work)
    }
}

/// The app that will receive dictated text, shown in the recording control row.
struct DictationTarget: Equatable {
    let name: String
    let icon: NSImage?
    static func == (lhs: DictationTarget, rhs: DictationTarget) -> Bool { lhs.name == rhs.name }
}
