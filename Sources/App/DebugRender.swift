import SwiftUI
import AppKit

/// Dev-only: renders notch states offscreen to /tmp so layout can be inspected
/// without screen-recording. Runs on launch only when DI_DEBUG_RENDER is set.
@MainActor
enum DebugRender {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["DI_DEBUG_RENDER"] != nil }

    static func run(metrics: NotchMetrics) {
        guard isEnabled else { return }
        if GoalStore.shared.goals.isEmpty {
            _ = GoalStore.shared.addGoal(name: "Save 100k", target: 100_000,
                                         deadline: Date().addingTimeInterval(120 * 86_400))
            _ = GoalStore.shared.logContribution(goalID: GoalStore.shared.goals[0].id,
                                                 amount: 42_000, label: "MTN stocks")
        }
        let np = NowPlayingInfo(title: "Never Gonna Give You Up (Official Remaster)",
                                artist: "Rick Astley", album: "Whenever You Need Somebody",
                                artwork: solidArt(), isPlaying: true, elapsed: 42, duration: 213)
        let cal = CalendarSnapshot(
            date: Date(),
            events: [
                NotchEvent(id: "1", title: "Design review", start: Date(), end: Date(), isAllDay: false, color: .pink),
                NotchEvent(id: "2", title: "1:1 with Sam", start: Date(), end: Date(), isAllDay: false, color: .blue),
            ],
            weatherText: "Cloudy", weatherSymbol: "cloud.fill", temperature: "18°")

        let fullBattery = BatteryInfo(level: 100, isCharging: true, isPluggedIn: true,
                                      isCharged: false, timeRemaining: nil, timeToFull: 24)

        render(.idle(.playing), np: np, cal: cal, name: "state_idle_playing", metrics: metrics)
        render(.idle(.calendar), np: np, cal: cal, name: "state_idle_calendar", metrics: metrics)
        render(.idle(.battery), np: nil, cal: nil, battery: fullBattery, name: "state_idle_battery", metrics: metrics)
        render(.idle(.goals), np: nil, cal: nil, name: "state_idle_goals", metrics: metrics)
        render(.hud(.sound(level: 0.6, muted: false)), np: nil, cal: nil, name: "state_hud_sound", metrics: metrics)
        render(.hud(.display(level: 0.4)), np: nil, cal: nil, name: "state_hud_display", metrics: metrics)
        render(.notification(TransientNotification(systemImage: "battery.100.bolt", tint: .green,
                title: "Charging", subtitle: nil, trailingText: "82%")),
               np: nil, cal: nil, name: "state_notification", metrics: metrics)
        render(.expanded(.playing), np: np, cal: cal, name: "state_expanded_playing", metrics: metrics)
        render(.expanded(.calendar), np: np, cal: cal, name: "state_expanded_calendar", metrics: metrics)
        render(.expanded(.duo), np: np, cal: cal, name: "state_expanded_duo", metrics: metrics)
        render(.fileTray(expanded: true), np: nil, cal: nil, name: "state_filetray_empty", metrics: metrics)

        render(.idle(.dictation), np: nil, cal: nil, name: "state_dictation_idle", metrics: metrics)
        render(.expanded(.dictation), np: nil, cal: nil, name: "state_dictation_hint", metrics: metrics)
        render(.dictation(.recording), np: nil, cal: nil, name: "state_dictation_recording", metrics: metrics)
        render(.dictation(.transcribing), np: nil, cal: nil, name: "state_dictation_transcribing", metrics: metrics)
        render(.dictation(.success("Hey, can you send me the notes from today")), np: nil, cal: nil, name: "state_dictation_success", metrics: metrics)

        renderPlain(DictationPane().padding(20).frame(width: 560, height: 980)
            .background(Color(nsColor: .windowBackgroundColor)), name: "settings_dictation")

        renderOnboarding(startIndex: 1, name: "onboarding_calendar")
        renderOnboarding(startIndex: 6, name: "onboarding_dictation")
    }

    private static func renderPlain<V: View>(_ view: V, name: String) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        }
    }

    private static func renderOnboarding(startIndex: Int, name: String) {
        let view = OnboardingView(startIndex: startIndex)
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        }
    }

    private static func solidArt() -> NSImage {
        let img = NSImage(size: NSSize(width: 60, height: 60))
        img.lockFocus()
        NSColor.systemPurple.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 60, height: 60)).fill()
        NSColor.systemPink.setFill()
        NSBezierPath(ovalIn: NSRect(x: 15, y: 15, width: 30, height: 30)).fill()
        img.unlockFocus()
        return img
    }

    private static func render(_ content: NotchContent, np: NowPlayingInfo?, cal: CalendarSnapshot?,
                               battery: BatteryInfo? = nil,
                               name: String, metrics: NotchMetrics) {
        let sizing = NotchSizing.size(for: content, metrics: metrics)
        let store = FileTrayStore()

        let view = ZStack {
            NotchShape(topCornerRadius: sizing.topRadius, bottomCornerRadius: sizing.bottomRadius)
                .fill(Color.black)
            Group {
                switch content {
                case .idle(let a):
                    IdleCompactView(activity: a, nowPlaying: np, calendar: cal, battery: battery, metrics: metrics)
                        .id(a)
                case .hud(let k):
                    HUDView(kind: k, metrics: metrics)
                case .notification(let n):
                    NotificationView(note: n, metrics: metrics)
                case .expanded(let a):
                    switch a {
                    case .playing, .none, .auto: NowPlayingExpandedView(info: np, metrics: metrics, glow: .pink)
                    case .calendar: CalendarExpandedView(snapshot: cal, metrics: metrics)
                    case .duo: DuoExpandedView(info: np, snapshot: cal, metrics: metrics)
                    case .dictation: DictationHintView(metrics: metrics)
                    case .battery: BatteryExpandedView(battery: nil, metrics: metrics)
                    case .stats: StatsExpandedView(stats: nil, metrics: metrics)
                    case .timer: TimerExpandedView(timer: nil, metrics: metrics)
                    case .clipboard: ClipboardExpandedView(metrics: metrics)
                    case .privacy: PrivacyExpandedView(privacy: nil, metrics: metrics)
                    case .claudeUsage: ClaudeStatsExpandedView(stats: nil, metrics: metrics)
                    case .goals: EmptyView()
                    }
                case .fileTray(let expanded):
                    FileTrayView(store: store, expanded: expanded, metrics: metrics)
                case let .dictation(phase):
                    DictationView(phase: phase, metrics: metrics, level: 0.7)
                case .mirror, .bare:
                    EmptyView()
                }
            }
            .frame(width: sizing.width, height: sizing.height)
            .clipShape(NotchShape(topCornerRadius: sizing.topRadius, bottomCornerRadius: sizing.bottomRadius))
        }
        .frame(width: sizing.width, height: sizing.height)
        .background(Color(red: 0.4, green: 0.55, blue: 0.25))

        let r = ImageRenderer(content: view)
        r.scale = 4
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
        }
    }
}
