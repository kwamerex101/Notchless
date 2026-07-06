import SwiftUI
import Combine

/// Owns all notch state and resolves it into a single `NotchContent` for the
/// view, applying priority: HUD > notification > expanded > idle > bare.
@MainActor
final class NotchViewModel: ObservableObject {
    // Interaction
    @Published var interaction: Interaction = .collapsed

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
    /// Live audio-band levels (low→high) from the system-audio tap, driving the
    /// now-playing visualizer. Empty when not capturing.
    @Published var musicSpectrum: [CGFloat] = []
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

    // Dictation (ListenToMe)
    @Published var dictation: DictationPhase?
    @Published var dictationLevel: CGFloat = 0.5
    @Published var dictationSpectrum: [CGFloat] = []
    let dictationSettings = DictationSettings.shared
    let dictationDictionary = DictationDictionary.shared
    let dictationHistory = DictationHistory.shared
    private var dictationDismiss: DispatchWorkItem?

    let settings: SettingsStore

    private var hudDismiss: DispatchWorkItem?
    private var notifDismiss: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var goalObserver: AnyCancellable?

    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let quickMorph = Animation.spring(response: 0.3, dampingFraction: 0.82)

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

    /// The single content the notch should render right now.
    var content: NotchContent {
        if let hud { return .hud(hud) }
        if let dictation { return .dictation(dictation) }
        if let notification { return .notification(notification) }
        if showMirror { return .mirror }
        if settings.fileTrayEnabled, isDropTargeted { return .fileTray(expanded: true) }
        if interaction == .expanded { return .expanded(activeExpandedActivity) }
        if settings.fileTrayEnabled, !fileTray.isEmpty {
            return .fileTray(expanded: interaction == .hovering)
        }

        if let activity = resolvedIdleActivity(hovering: interaction == .hovering) {
            return .idle(activity)
        }
        return .bare
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
        if let battery, battery.isPluggedIn || battery.isCharging { result.append(.battery) }
        return result
    }

    /// Everything the user can swipe through: the live activities plus the
    /// always-available info pages (calendar, stats). Only browsable while at
    /// least one activity is live — the notch stays bare when nothing is.
    var carouselActivities: [NotchActivity] {
        var result = liveActivities
        for page in [NotchActivity.calendar, .stats, .claudeUsage] where !result.contains(page) {
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

    /// Advances the Auto carousel to the next page (horizontal swipe) — through
    /// the live activities and the calendar/stats pages.
    func cycleLiveActivity() {
        guard !liveActivities.isEmpty else { return }
        let carousel = carouselActivities
        guard carousel.count >= 2 else { return }
        let current = manualActivity.flatMap { carousel.contains($0) ? $0 : nil } ?? liveActivities[0]
        let index = carousel.firstIndex(of: current) ?? 0
        manualActivity = carousel[(index + 1) % carousel.count]
    }

    /// Which activity a click/hover expands into.
    var activeExpandedActivity: NotchActivity {
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
        case .stats: return stats != nil
        case .timer: return true  // always rests so it can be started from the notch
        case .clipboard: return true
        case .todos: return settings.todosEnabled && !todos.isEmpty
        case .privacy: return privacy?.isActive ?? false
        case .claudeUsage: return claudeStats != nil
        case .goals: return settings.goalsEnabled && goals.hasActiveGoals
        }
    }

    // MARK: - Interaction

    func hoverChanged(_ hovering: Bool) {
        collapseWork?.cancel()
        if hovering {
            // Expand directly on hover — no click required.
            if interaction != .expanded {
                if settings.hapticFeedback { HapticService.tap() }
                withAnimation(Self.morph) { interaction = .expanded }
            }
        } else {
            // Grace delay before collapsing so brief exits don't flicker.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                withAnimation(Self.morph) { self.interaction = .collapsed }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    func toggleMirror() {
        withAnimation(Self.morph) { showMirror.toggle() }
    }

    /// Drives the dictation notch activity. Terminal phases (success/error)
    /// auto-dismiss after a beat; pass nil to clear immediately.
    func setDictation(_ phase: DictationPhase?) {
        dictationDismiss?.cancel()
        withAnimation(Self.quickMorph) { dictation = phase }
        if let phase, !phase.isActive {
            let work = DispatchWorkItem { [weak self] in
                withAnimation(Self.morph) { self?.dictation = nil }
            }
            dictationDismiss = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
        }
    }

    /// A click keeps the notch open (buttons handle their own taps); it never
    /// collapses, so clicking inside the expanded panel is safe.
    func tapped() {
        withAnimation(Self.morph) { interaction = .expanded }
    }

    func collapse() {
        collapseWork?.cancel()
        withAnimation(Self.morph) { interaction = .collapsed }
    }

    // MARK: - HUD

    func showHUD(_ kind: HUDKind) {
        hudDismiss?.cancel()
        withAnimation(Self.quickMorph) { hud = kind }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.morph) { self?.hud = nil }
        }
        hudDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    // MARK: - Notifications

    func show(_ note: TransientNotification) {
        notifDismiss?.cancel()
        withAnimation(Self.quickMorph) { notification = note }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.morph) { self?.notification = nil }
        }
        notifDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + note.duration, execute: work)
    }
}
