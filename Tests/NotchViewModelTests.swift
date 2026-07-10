import XCTest
@testable import Notchless

/// Content-priority resolution and carousel/live-activity ordering in
/// NotchViewModel — the state machine that decides what the notch shows.
@MainActor
final class NotchViewModelTests: XCTestCase {
    private var saved: (idle: NotchActivity, stats: Bool, claude: Bool, todos: Bool, goals: Bool)?

    override func setUp() {
        super.setUp()
        let s = SettingsStore.shared
        saved = (s.idleActivity, s.statsEnabled, s.claudeUsageEnabled, s.todosEnabled, s.goalsEnabled)
        s.idleActivity = .auto
        // Disable the shared-store-backed activities so real on-disk tasks/goals
        // on the dev machine don't make the notch "live" during these tests.
        s.todosEnabled = false
        s.goalsEnabled = false
    }

    override func tearDown() {
        if let saved {
            let s = SettingsStore.shared
            s.idleActivity = saved.idle
            s.statsEnabled = saved.stats
            s.claudeUsageEnabled = saved.claude
            s.todosEnabled = saved.todos
            s.goalsEnabled = saved.goals
        }
        super.tearDown()
    }

    private func playing() -> NowPlayingInfo {
        NowPlayingInfo(title: "T", artist: "A", album: nil, artwork: nil,
                       isPlaying: true, elapsed: 0, duration: 100,
                       bundleIdentifier: nil, appName: nil)
    }

    // MARK: Content priority

    func test_bareWhenNothingLiveInAuto() {
        let model = NotchViewModel()
        XCTAssertEqual(model.content, .bare)
    }

    func test_hudBeatsEverything() {
        let model = NotchViewModel()
        model.nowPlaying = playing()
        model.hud = .sound(level: 0.5, muted: false)
        if case .hud = model.content {} else { XCTFail("HUD should win, got \(model.content)") }
    }

    func test_dictationBeatsNotification() {
        let model = NotchViewModel()
        model.notification = TransientNotification(systemImage: "bolt", tint: .green, title: "x")
        model.dictation = .recording
        if case .dictation = model.content {} else { XCTFail("dictation should beat notification") }
    }

    func test_expandedShowsActivity() {
        let model = NotchViewModel()
        model.nowPlaying = playing()
        model.tapped()   // → expanded
        if case .expanded = model.content {} else { XCTFail("should be expanded, got \(model.content)") }
    }

    func test_idlePlayingWhenMediaLive() {
        let model = NotchViewModel()
        model.nowPlaying = playing()
        if case .idle(.playing) = model.content {} else {
            XCTFail("should rest on playing, got \(model.content)")
        }
    }

    // MARK: Fullscreen

    func test_fullscreenRestsBareEvenWithLiveActivity() {
        let s = SettingsStore.shared
        let saved = s.collapseInFullscreen
        defer { s.collapseInFullscreen = saved }
        s.collapseInFullscreen = true

        let model = NotchViewModel()
        model.nowPlaying = playing()
        model.fullscreenActive = true
        XCTAssertEqual(model.content, .bare, "resting wings would cover fullscreen content")
    }

    func test_fullscreenStillShowsTransientsAndHover() {
        let s = SettingsStore.shared
        let saved = s.collapseInFullscreen
        defer { s.collapseInFullscreen = saved }
        s.collapseInFullscreen = true

        let model = NotchViewModel()
        model.nowPlaying = playing()
        model.fullscreenActive = true
        // A HUD is transient and intentional — it must still surface.
        model.hud = .sound(level: 0.5, muted: false)
        if case .hud = model.content {} else { XCTFail("HUD should show in fullscreen") }
        model.hud = nil
        // Hover is explicit user intent — the activity comes back.
        model.interaction = .hovering
        if case .idle(.playing) = model.content {} else {
            XCTFail("hover should restore the activity, got \(model.content)")
        }
    }

    func test_fullscreenCollapseRespectsOptOut() {
        let s = SettingsStore.shared
        let saved = s.collapseInFullscreen
        defer { s.collapseInFullscreen = saved }
        s.collapseInFullscreen = false

        let model = NotchViewModel()
        model.nowPlaying = playing()
        model.fullscreenActive = true
        if case .idle(.playing) = model.content {} else {
            XCTFail("opting out should keep the resting activity, got \(model.content)")
        }
    }

    // MARK: Live activity ordering

    func test_privacySortsFirstAmongLiveActivities() {
        let model = NotchViewModel()
        model.nowPlaying = playing()
        model.privacy = PrivacyStatus(cameraActive: true, micActive: false)
        XCTAssertEqual(model.liveActivities.first, .privacy)
    }

    func test_batteryOnlyLiveWhenChargingOrPlugged() {
        let model = NotchViewModel()
        model.battery = BatteryInfo(level: 80, isCharging: false, isPluggedIn: false,
                                    isCharged: false, timeRemaining: nil, timeToFull: nil)
        XCTAssertFalse(model.liveActivities.contains(.battery))
        model.battery = BatteryInfo(level: 80, isCharging: true, isPluggedIn: true,
                                    isCharged: false, timeRemaining: nil, timeToFull: nil)
        XCTAssertTrue(model.liveActivities.contains(.battery))
    }

    // MARK: Carousel

    func test_cycleWrapsAround() {
        SettingsStore.shared.statsEnabled = true
        SettingsStore.shared.claudeUsageEnabled = true
        let model = NotchViewModel()
        model.nowPlaying = playing()
        let carousel = model.carouselActivities
        XCTAssertGreaterThanOrEqual(carousel.count, 2)
        // Cycle a full loop and land back where we started.
        let start = model.activeExpandedActivity
        for _ in carousel { model.cycleLiveActivity() }
        XCTAssertEqual(model.activeExpandedActivity, start)
    }
}
