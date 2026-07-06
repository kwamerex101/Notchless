import XCTest
@testable import Notchless

@MainActor
final class NotchTabBarModelTests: XCTestCase {
    /// These tests exercise the carousel with `.stats`/`.claudeUsage` present, so
    /// they need those pages enabled regardless of the machine's saved settings.
    /// Snapshot + restore the real values so running tests never mutates the
    /// user's config.
    private var saved: (idle: NotchActivity, stats: Bool, claude: Bool)?

    override func setUp() {
        super.setUp()
        let s = SettingsStore.shared
        saved = (s.idleActivity, s.statsEnabled, s.claudeUsageEnabled)
        s.statsEnabled = true
        s.claudeUsageEnabled = true
    }

    override func tearDown() {
        if let saved {
            let s = SettingsStore.shared
            s.idleActivity = saved.idle
            s.statsEnabled = saved.stats
            s.claudeUsageEnabled = saved.claude
        }
        super.tearDown()
    }

    /// A model with one live activity (media) so the carousel has ≥2 pages:
    /// [.playing, .calendar, .stats, .claudeUsage].
    private func makeModel() -> NotchViewModel {
        SettingsStore.shared.idleActivity = .auto
        let model = NotchViewModel()
        model.nowPlaying = NowPlayingInfo(
            title: "T", artist: "A", album: nil, artwork: nil,
            isPlaying: true, elapsed: 0, duration: 100,
            bundleIdentifier: nil, appName: nil
        )
        return model
    }

    func test_select_makesActivityTheActiveExpandedPage() {
        let model = makeModel()
        XCTAssertTrue(model.carouselActivities.contains(.stats))
        model.select(.stats)
        XCTAssertEqual(model.activeExpandedActivity, .stats)
    }

    func test_select_ignoresActivityNotInCarousel() {
        let model = makeModel()
        model.select(.stats)                 // valid, becomes active
        XCTAssertFalse(model.carouselActivities.contains(.timer))
        model.select(.timer)                 // invalid → ignored
        XCTAssertEqual(model.activeExpandedActivity, .stats)
    }

    func test_everyActivityHasNonEmptyTabGlyph() {
        for activity in NotchActivity.allCases {
            XCTAssertFalse(activity.tabGlyph.isEmpty, "\(activity) missing glyph")
        }
    }

    func test_select_worksInFixedIdleMode() {
        SettingsStore.shared.idleActivity = .none
        let model = NotchViewModel()                 // nothing live
        XCTAssertTrue(model.carouselActivities.contains(.stats))
        model.select(.stats)
        XCTAssertEqual(model.activeExpandedActivity, .stats)
    }

    func test_collapse_resetsManualPickInFixedMode() {
        SettingsStore.shared.idleActivity = .none
        let model = NotchViewModel()
        model.select(.stats)
        XCTAssertEqual(model.activeExpandedActivity, .stats)
        model.collapse()
        // Fixed .none mode with nothing live falls back to .calendar.
        XCTAssertEqual(model.activeExpandedActivity, .calendar)
    }

    func test_collapse_keepsManualPickInAutoMode() {
        SettingsStore.shared.idleActivity = .auto
        let model = NotchViewModel()
        model.nowPlaying = NowPlayingInfo(
            title: "T", artist: "A", album: nil, artwork: nil,
            isPlaying: true, elapsed: 0, duration: 100,
            bundleIdentifier: nil, appName: nil
        )
        model.select(.stats)
        model.collapse()
        XCTAssertEqual(model.activeExpandedActivity, .stats)  // sticky in Auto
    }
}
