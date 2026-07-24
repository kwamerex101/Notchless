import AppKit
import SwiftUI

/// Debug-only: renders every notch state and every settings pane to PNG files
/// under `outputDirectory`, so a design-fidelity diff can be scripted instead
/// of driven by hand. Triggered by `--dump-states [dir]` (see `NotchlessApp`).
/// Not gated behind `#if DEBUG` — the release build must be able to run it too.
@MainActor
enum DebugStateDump {
    static func run(outputDirectory: URL) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let metrics = NotchMetrics(
            notchWidth: 196,
            notchHeight: 32,
            notchCenterX: 756,
            screenTopY: 982,
            hasRealNotch: true
        )

        let model = NotchViewModel(settings: makeIsolatedSettings())
        seed(model, outputDirectory: outputDirectory)

        var written = 0

        // MARK: Bare
        written += renderNotch(.bare, model: model, metrics: metrics, slug: "notch-bare", outputDirectory: outputDirectory)

        // MARK: Idle / expanded — every NotchActivity
        for activity in NotchActivity.allCases {
            let slug = activity.rawValue.lowercased()
            written += renderNotch(.idle(activity), model: model, metrics: metrics,
                                   slug: "notch-idle-\(slug)", outputDirectory: outputDirectory)
            written += renderNotch(.expanded(activity), model: model, metrics: metrics,
                                   slug: "notch-expanded-\(slug)", outputDirectory: outputDirectory)
        }

        // MARK: HUDs — spec §3: volume 65% with the percentage label visible,
        // brightness 72%. The label is gated by `hudShowPercentageLabel`,
        // turned on in `seed(_:outputDirectory:)`.
        written += renderNotch(.hud(.sound(level: 0.65, muted: false)), model: model, metrics: metrics,
                               slug: "notch-hud-sound", outputDirectory: outputDirectory)
        written += renderNotch(.hud(.display(level: 0.72)), model: model, metrics: metrics,
                               slug: "notch-hud-display", outputDirectory: outputDirectory)

        // MARK: Notifications — the four semantic banners from spec §3's
        // "Notification banners" table. Tints match what the real callers
        // pass (NotificationsController.bluetooth.onConnect uses `.green`,
        // not the spec's blue — that mismatch is real and worth seeing in
        // the diff), so the view's tint→semantic mapping stays under test.
        // Tints match what `NotificationsController` actually passes today
        // (see Sources/Services/NotificationsController.swift) — the harness
        // used to hardcode system-color guesses (`.green`/`.indigo`/`.orange`)
        // that no longer matched the real caller, which itself moved to
        // passing `NotchTheme.*` tokens directly (spec §1 "Semantic colour").
        let notificationSamples: [(String, TransientNotification)] = [
            ("charging", TransientNotification(systemImage: "battery.100.bolt", tint: NotchTheme.positive,
                                               title: "Charging", subtitle: "MacBook Pro — 2:14 until full",
                                               trailingText: "87%")),
            ("bluetooth", TransientNotification(systemImage: "headphones", tint: NotchTheme.link,
                                                title: "AirPods Pro", subtitle: "Connected",
                                                trailingText: "72%")),
            ("focus", TransientNotification(systemImage: "moon.fill", tint: NotchTheme.focus,
                                            title: "Do Not Disturb", subtitle: "Focus on until 6:00 PM",
                                            trailingText: nil)),
            ("nointernet", TransientNotification(systemImage: "wifi.slash", tint: NotchTheme.warning,
                                                 title: "No Internet", subtitle: "Wi-Fi is connected without internet",
                                                 trailingText: nil)),
        ]
        for (name, note) in notificationSamples {
            written += renderNotch(.notification(note), model: model, metrics: metrics,
                                   slug: "notch-notification-\(name)", outputDirectory: outputDirectory)
        }

        // MARK: File Tray
        written += renderNotch(.fileTray(expanded: false), model: model, metrics: metrics,
                               slug: "notch-filetray-collapsed", outputDirectory: outputDirectory)
        written += renderNotch(.fileTray(expanded: true), model: model, metrics: metrics,
                               slug: "notch-filetray-expanded", outputDirectory: outputDirectory)

        // MARK: Mirror (camera preview — NSViewRepresentable, always partial)
        written += renderNotch(.mirror, model: model, metrics: metrics,
                               slug: "notch-mirror", outputDirectory: outputDirectory, partial: true)

        // MARK: Dictation — every DictationPhase
        let dictationSamples: [(String, DictationPhase)] = [
            ("recording", .recording),
            ("transcribing", .transcribing),
            ("cleaning", .cleaning),
            ("success", .success("Hey, can you send me the notes from today's standup?")),
            ("error", .error("Couldn't hear that")),
        ]
        for (name, phase) in dictationSamples {
            written += renderNotch(.dictation(phase), model: model, metrics: metrics,
                                   slug: "notch-dictation-\(name)", outputDirectory: outputDirectory)
        }
        model.debugContentOverride = nil

        // MARK: Settings panes — every SettingsSection
        for section in SettingsSection.allCases {
            let slug = "settings-\(section.rawValue.lowercased())"
            written += renderSettings(section, model: model, slug: slug, outputDirectory: outputDirectory)
        }

        print("Wrote \(written) files to \(outputDirectory.path)")
    }

    // MARK: - Seed data

    /// A UserDefaults suite private to this run, so the harness never reads or
    /// mutates the signed-in user's real settings — and a no-op iCloud store so
    /// neither the `@Stored` setters nor `SettingsStore.persist` can leak a
    /// write into `NSUbiquitousKeyValueStore.default`. See the two guards
    /// below for why no cloud write can happen during a dump.
    private static func makeIsolatedSettings() -> SettingsStore {
        // A single fixed suite (cleared each run) rather than a per-run
        // `.<UUID>` name, so repeated dumps don't leave a trail of stray
        // plists behind.
        let suite = "com.rexdanquah.Notchless.debug-dump"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        // Start with iCloud sync OFF *before* the store loads it, so
        // `SettingsStore.persist`'s hardcoded-`cloud` write path (gated on
        // `syncViaICloud`) never fires for any seeded @Published change.
        defaults.set(false, forKey: "syncViaICloud")
        // Inject a no-op KVS so the `@Stored` setters — which write to `kvs`
        // unconditionally (no `syncViaICloud` gate) — can't reach real iCloud
        // either. `hudShowPercentageLabel = true` in `seed` hits this path.
        let settings = SettingsStore(defaults: defaults, kvs: NoOpKeyValueStore())
        // `ProgressiveBlur` is an `NSViewRepresentable` — `ImageRenderer` can't
        // rasterize it (same class of issue as the Mirror camera preview, see
        // `partial:` below). Off for the harness only, so expanded captures
        // don't carry an unrasterized subview.
        settings.progressiveBlur = false
        return settings
    }

    /// Fills the view model with realistic placeholder content, matching the
    /// design's sample data where the model allows it. Fields backed by a live
    /// service with no offline equivalent (Claude usage history is read from
    /// real transcripts, Goals/Tasks are the user's shared iCloud-synced
    /// stores) are left as-is rather than faked.
    private static func seed(_ model: NotchViewModel, outputDirectory: URL) {
        model.nowPlaying = NowPlayingInfo(
            title: "Golden Hour",
            artist: "JVKE",
            album: "This Is What Ails Me",
            artwork: sampleArtwork(),
            isPlaying: true,
            elapsed: 96,
            duration: 202,
            bundleIdentifier: "com.apple.Music",
            appName: "Music"
        )

        let today = Date()
        // Duo/Calendar (spec §3 "Expanded · Duo"): a real 2:00–2:45 PM event,
        // not `start == end` — that collapsed to a nonsensical
        // "3:51 AM – 3:51 AM" readout since `DuoExpandedView` formats
        // `first.start`/`first.end` verbatim.
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let eventStart = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        let eventEnd = cal.date(bySettingHour: 14, minute: 45, second: 0, of: today) ?? today
        model.calendar = CalendarSnapshot(
            date: today,
            events: [
                NotchEvent(id: "1", title: "Design review", start: eventStart, end: eventEnd, isAllDay: false, color: .pink),
                NotchEvent(id: "2", title: "1:1 with Sam", start: eventStart, end: eventEnd, isAllDay: false, color: .blue),
            ],
            weatherText: "Cloudy",
            weatherSymbol: "cloud.fill",
            temperature: "18°"
        )

        model.battery = BatteryInfo(level: 87, isCharging: true, isPluggedIn: true,
                                    isCharged: false, timeRemaining: nil, timeToFull: 24)

        // Wings tab strip (spec §2): needs a few carousel pages to show more
        // than one glyph, and the right wing reads `model.battery` (already
        // seeded to 87% above).
        model.settings.statsEnabled = true
        model.settings.claudeUsageEnabled = true

        // HUD percentage label (spec §3 "HUD"): off by default, on for the dump.
        model.settings.hudShowPercentageLabel = true

        model.stats = SystemStats(cpu: 0.38, memoryUsed: 8_500_000_000, memoryTotal: 16_000_000_000,
                                  networkDown: 1_240_000, networkUp: 312_000)

        model.notchTimer = NotchTimerInfo(total: 900, remaining: 763, isRunning: true)  // 12:43 left

        model.privacy = PrivacyStatus(cameraActive: false, micActive: true)

        model.claudeStats = ClaudeUsageStats(
            input: 4_200_000, output: 980_000, cache: 1_650_000,
            daily: Array((0..<14).map { offset in
                DayUsage(date: Calendar.current.date(byAdding: .day, value: -offset, to: today) ?? today,
                        tokens: 300_000 + offset * 15_000, cost: 4.2 + Double(offset) * 0.3)
            }.reversed()),
            sessionCost: 8.42, sessionResetIn: 3 * 3600 + 12 * 60,
            weekCost: 58.10, todayCost: 8.42, yesterdayCost: 11.05, last30Cost: 210.75
        )

        // File Tray (spec §3 "File Tray"): three real (empty) sample files, so
        // the expanded tray shows three tiles and the collapsed pill reads "3".
        let sampleDir = outputDirectory.appendingPathComponent("_sample-files", isDirectory: true)
        try? FileManager.default.createDirectory(at: sampleDir, withIntermediateDirectories: true)
        let sampleNames = ["Design.pdf", "hero@2x.png", "notes.md"]
        let sampleURLs = sampleNames.map { sampleDir.appendingPathComponent($0) }
        for url in sampleURLs where !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        model.fileTray.add(sampleURLs)

        // Meetings: construct the real controller (mirrors AppDelegate) so
        // .idle(.meeting) / .expanded(.meeting) render their actual view instead
        // of falling back to an empty placeholder. Capture never starts — phase
        // is driven straight to `.recording` via the debug-only seam below
        // (spec §3 "Idle · Meeting recording" / "Expanded · Meeting").
        model.meeting = MeetingController(
            capture: MeetingCaptureService(systemTap: SystemAudioTap(model: model)),
            pipeline: MeetingTranscriptionPipeline(),
            summarizer: MeetingSummarizer(client: AnthropicMinutesAPIClient(keyProvider: { "" }),
                                          model: "claude-sonnet-5"),
            store: MeetingStore(directory: outputDirectory.appendingPathComponent("_meeting-store"))
        )
        model.meeting?.debugSetRecording(elapsed: 12 * 60 + 4)  // 12:04

        // Dictation recording footer (spec §3 "Dictation states → Recording"):
        // `Notes · Obsidian · 0:23 · esc Cancel`. These live on the model
        // directly (not the `NotchContent` enum), so seeding them once here
        // covers the `notch-dictation-recording` render.
        model.dictationModeName = "Notes"
        model.dictationTarget = DictationTarget(name: "Obsidian", icon: nil)
        model.dictationStartedAt = today.addingTimeInterval(-23)

        // Goals/Tasks are the user's real shared stores (GoalStore.shared /
        // TodoStore.shared, iCloud-synced) — rendered as-is rather than
        // seeded, so this tool never writes fake data into them.
    }

    private static func sampleArtwork() -> NSImage {
        let img = NSImage(size: NSSize(width: 200, height: 200))
        img.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 200, height: 200)).fill()
        NSColor.systemPink.setFill()
        NSBezierPath(ovalIn: NSRect(x: 40, y: 40, width: 120, height: 120)).fill()
        img.unlockFocus()
        return img
    }

    // MARK: - Rendering

    /// Neutral desktop-grey card the design mockups show every notch state
    /// against (`docs/flat-dark-spec.md` intro) — the notch panel itself is
    /// transparent outside `NotchShape`, so without this backing the hairline
    /// and non-rectangular corners would render onto plain white/clear.
    private static let cardBackground = Color(red: 0x2e / 255, green: 0x30 / 255, blue: 0x37 / 255)

    /// Renders one notch state through the same offscreen-window path as
    /// Settings (`writeWindowRenderedPNG`), sized to that state's
    /// `NotchSizing` plus a margin so the neutral card frames it like the
    /// design mockups. `ImageRenderer` renders in a single synchronous pass
    /// with no real window behind it, so it can't lay out `List`/`ScrollView`/
    /// `TextField` or rasterize `NSViewRepresentable` content — `List`
    /// (Todos), `ScrollView`+`TextField` (Goals), and `ScrollView` (File Tray
    /// tiles) all came out as a broken-glyph box or an empty area under it.
    ///
    /// `partial` marks states that still embed an `NSViewRepresentable` this
    /// path can't fully exercise offscreen — the camera preview in Mirror has
    /// no live frames without a running capture session — so the printed line
    /// says so.
    ///
    /// `.notchDropTargetDisabled` turns off `NotchRootView`'s `.onDrop` file
    /// target for this render only: rendering an `.onDrop`-registered view
    /// offscreen paints AppKit's default drag-destination highlight
    /// permanently around it instead of only during a live drag, which showed
    /// up as a bright halo behind every notch state — bare and idle included,
    /// not just expanded. File Tray drag & drop in the real running app is
    /// untouched; the environment default is `false`.
    @discardableResult
    private static func renderNotch(_ content: NotchContent, model: NotchViewModel, metrics: NotchMetrics,
                                    slug: String, outputDirectory: URL, partial: Bool = false) -> Int {
        model.debugContentOverride = content
        let sizing = NotchSizing.size(for: content, metrics: metrics, dictationSettled: model.dictationSettled)
        let margin: CGFloat = 32
        let canvasSize = NSSize(width: sizing.width + margin * 2, height: sizing.height + margin * 2)

        let view = ZStack(alignment: .top) {
            cardBackground
            NotchRootView(model: model, metrics: metrics)
                .environment(\.notchDropTargetDisabled, true)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)

        return writeWindowRenderedPNG(view, size: canvasSize, slug: slug,
                                      outputDirectory: outputDirectory, partial: partial)
    }

    /// Renders the whole Settings window — sidebar included — with `section`
    /// selected, at the spec's 880x620 chrome size (spec §5). Uses
    /// `SettingsView`'s `initialSelection` seam rather than duplicating its
    /// sidebar/content switch here.
    @discardableResult
    private static func renderSettings(_ section: SettingsSection, model: NotchViewModel,
                                       slug: String, outputDirectory: URL) -> Int {
        guard let meeting = model.meeting else {
            print("\(slug).png — FAILED: model.meeting not seeded")
            return 0
        }
        let view = SettingsView(settings: model.settings, meeting: meeting, initialSelection: section)
        return writeWindowRenderedPNG(view, size: NSSize(width: 880, height: 620),
                                      slug: slug, outputDirectory: outputDirectory)
    }

    /// Rasterizes `view` at `size` via a real offscreen `NSWindow` +
    /// `NSHostingView` and writes `<slug>.png` into `outputDirectory`.
    ///
    /// A bare `NSHostingView` never gets laid out — content like a
    /// `ScrollView` or `List` inside it needs an actual AppKit
    /// window/layout/display cycle to receive a proposed size, which
    /// `ImageRenderer`'s single synchronous pass never provides. Parking a
    /// real (off-screen) window and forcing a display pass gives SwiftUI that
    /// cycle, and as a bonus rasterizes `NSViewRepresentable` content
    /// correctly too.
    @discardableResult
    private static func writeWindowRenderedPNG<V: View>(_ view: V, size: NSSize, slug: String,
                                                         outputDirectory: URL, partial: Bool = false) -> Int {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(size)
        // Well off the visible desktop, but still ordered in — AppKit only
        // runs a real layout/display cycle for a window that's actually on
        // screen (even if that "screen" is outside every display's bounds).
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            print("\(slug).png — FAILED to render")
            return 0
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("\(slug).png — FAILED to render")
            return 0
        }
        let url = outputDirectory.appendingPathComponent("\(slug).png")
        do {
            try png.write(to: url)
            print("\(slug).png\(partial ? "  (partial: contains NSView-backed content)" : "")")
            return 1
        } catch {
            print("\(slug).png — FAILED to write: \(error)")
            return 0
        }
    }
}

/// A `KeyValueStore` that drops every write, injected into the harness's
/// `SettingsStore` so its `@Stored` setters (which mirror to `kvs`
/// unconditionally) can never touch the real `NSUbiquitousKeyValueStore.default`
/// during a `--dump-states` run.
private final class NoOpKeyValueStore: KeyValueStore {
    func object(forKey key: String) -> Any? { nil }
    func set(_ value: Any?, forKey key: String) {}
    @discardableResult func synchronize() -> Bool { true }
}
