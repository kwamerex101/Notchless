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
    /// Vibrant color sampled from the current artwork (album-art glow).
    @Published var artworkColor: Color?

    // File Tray
    let fileTray = FileTrayStore()
    @Published var isDropTargeted = false

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

    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let quickMorph = Animation.spring(response: 0.3, dampingFraction: 0.82)

    init(settings: SettingsStore? = nil) {
        self.settings = settings ?? .shared
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

    /// The concrete activity to rest in the notch at idle, or nil for a bare
    /// notch. In Auto mode this is whatever Live Activity is currently live.
    private func resolvedIdleActivity(hovering: Bool) -> NotchActivity? {
        switch settings.idleActivity {
        case .none:
            return nil
        case .auto:
            // Show only what's actually happening — nothing otherwise.
            return autoIdleActivity()
        default:
            let idle = settings.idleActivity
            if hovering { return idle }
            return hasIdleContent(idle) ? idle : nil
        }
    }

    /// Ordered Live-Activity providers for Auto mode; the first live one wins.
    /// New activities (timers, screen recording, AirDrop…) slot in here.
    private func autoIdleActivity() -> NotchActivity? {
        if nowPlaying != nil { return .playing }
        return nil
    }

    /// Which activity a click/hover expands into.
    var activeExpandedActivity: NotchActivity {
        switch settings.idleActivity {
        case .none, .auto:
            return nowPlaying != nil ? .playing : .calendar
        default:
            return settings.idleActivity
        }
    }

    private func hasIdleContent(_ activity: NotchActivity) -> Bool {
        switch activity {
        case .none: return false
        case .auto: return autoIdleActivity() != nil
        case .playing: return nowPlaying != nil
        case .calendar: return true
        case .duo: return nowPlaying != nil || (calendar?.hasEvents ?? false) || settings.forceEnableActivity
        case .dictation: return true  // the mic-ready cue always rests in the notch
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
