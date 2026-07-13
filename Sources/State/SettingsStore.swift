import SwiftUI
import Combine

/// Which display the (simulated) notch is drawn on.
enum SimulatedDisplay: String, CaseIterable, Codable {
    case builtIn
    case main
    case active

    var title: String {
        switch self {
        case .builtIn: return "Built-in display"
        case .main: return "Main display"
        case .active: return "Active display"
        }
    }

    var systemImage: String {
        switch self {
        case .builtIn: return "laptopcomputer"
        case .main: return "display"
        case .active: return "display.2"
        }
    }
}

/// All persisted user preferences, mirroring Alcove's settings surface.
/// Backed by `UserDefaults`, optionally mirrored to iCloud key-value store.
@MainActor
final class SettingsStore: ObservableObject, StoredHost {
    static let shared = SettingsStore()

    /// Injected storage seam (for `@Stored` and tests). The existing
    /// persist/load/cloud-mirror logic below keeps using its own `cloud`
    /// reference — `NSUbiquitousKeyValueStore`'s typed convenience accessors
    /// (`.bool(forKey:)`, `.string(forKey:)`, …) aren't part of the
    /// `KeyValueStore` protocol, so rerouting that logic through `kvs` isn't
    /// a trivially-safe change; left as-is per the task brief.
    let defaults: UserDefaults
    let kvs: KeyValueStore
    private let cloud = NSUbiquitousKeyValueStore.default

    // General
    @Published var launchAtLogin: Bool { didSet { persist(Keys.launchAtLogin, launchAtLogin, oldValue != launchAtLogin) } }
    @Published var syncViaICloud: Bool { didSet { persist(Keys.syncViaICloud, syncViaICloud, oldValue != syncViaICloud) } }
    @Published var hideInFullscreen: Bool { didSet { persist(Keys.hideInFullscreen, hideInFullscreen, oldValue != hideInFullscreen) } }
    @Published var collapseInFullscreen: Bool { didSet { persist(Keys.collapseInFullscreen, collapseInFullscreen, oldValue != collapseInFullscreen) } }
    @Published var hideInMissionControl: Bool { didSet { persist(Keys.hideInMissionControl, hideInMissionControl, oldValue != hideInMissionControl) } }
    @Published var hideFromScreenCapture: Bool { didSet { persist(Keys.hideFromScreenCapture, hideFromScreenCapture, oldValue != hideFromScreenCapture) } }
    @Published var forceSimulatedNotch: Bool { didSet { persist(Keys.forceSimulatedNotch, forceSimulatedNotch, oldValue != forceSimulatedNotch) } }
    @Published var simulatedDisplay: SimulatedDisplay { didSet { persist(Keys.simulatedDisplay, simulatedDisplay.rawValue, oldValue != simulatedDisplay) } }

    // Idle activity
    @Published var idleActivity: NotchActivity { didSet { persist(Keys.idleActivity, idleActivity.rawValue, oldValue != idleActivity) } }
    @Published var idleMostRecent: Bool { didSet { persist(Keys.idleMostRecent, idleMostRecent, oldValue != idleMostRecent) } }
    @Published var forceEnableActivity: Bool { didSet { persist(Keys.forceEnableActivity, forceEnableActivity, oldValue != forceEnableActivity) } }

    // Appearance
    @Published var glassStyle: GlassStyle { didSet { persist(Keys.glassStyle, glassStyle.rawValue, oldValue != glassStyle) } }
    @Published var glassIntensity: Double { didSet { persist(Keys.glassIntensity, glassIntensity, oldValue != glassIntensity) } }

    // Behaviour
    @Published var progressiveBlur: Bool { didSet { persist(Keys.progressiveBlur, progressiveBlur, oldValue != progressiveBlur) } }
    @Published var hapticFeedback: Bool { didSet { persist(Keys.hapticFeedback, hapticFeedback, oldValue != hapticFeedback) } }
    @Published var albumArtGlow: Bool { didSet { persist(Keys.albumArtGlow, albumArtGlow, oldValue != albumArtGlow) } }

    // Trackpad feedback (system-wide haptics + click sounds)
    @Published var trackpadFeedbackEnabled: Bool { didSet { persist(Keys.trackpadFeedbackEnabled, trackpadFeedbackEnabled, oldValue != trackpadFeedbackEnabled) } }
    @Published var trackpadHapticsEnabled: Bool { didSet { persist(Keys.trackpadHapticsEnabled, trackpadHapticsEnabled, oldValue != trackpadHapticsEnabled) } }
    @Published var trackpadSoundEnabled: Bool { didSet { persist(Keys.trackpadSoundEnabled, trackpadSoundEnabled, oldValue != trackpadSoundEnabled) } }
    @Published var trackpadFeedbackScroll: Bool { didSet { persist(Keys.trackpadFeedbackScroll, trackpadFeedbackScroll, oldValue != trackpadFeedbackScroll) } }
    @Published var trackpadFeedbackClick: Bool { didSet { persist(Keys.trackpadFeedbackClick, trackpadFeedbackClick, oldValue != trackpadFeedbackClick) } }
    @Published var trackpadHapticStrength: HapticStrength { didSet { persist(Keys.trackpadHapticStrength, trackpadHapticStrength.rawValue, oldValue != trackpadHapticStrength) } }
    @Published var trackpadSoundVoice: String { didSet { persist(Keys.trackpadSoundVoice, trackpadSoundVoice, oldValue != trackpadSoundVoice) } }
    @Published var trackpadSoundVolume: Double { didSet { persist(Keys.trackpadSoundVolume, trackpadSoundVolume, oldValue != trackpadSoundVolume) } }
    @Published var trackpadGesturesEnabled: Bool { didSet { persist(Keys.trackpadGesturesEnabled, trackpadGesturesEnabled, oldValue != trackpadGesturesEnabled) } }

    // Notifications
    @Published var batteryEnabled: Bool { didSet { persist(Keys.batteryEnabled, batteryEnabled, oldValue != batteryEnabled) } }
    @Published var connectivityEnabled: Bool { didSet { persist(Keys.connectivityEnabled, connectivityEnabled, oldValue != connectivityEnabled) } }
    @Published var focusEnabled: Bool { didSet { persist(Keys.focusEnabled, focusEnabled, oldValue != focusEnabled) } }
    @Published var displayHUDEnabled: Bool { didSet { persist(Keys.displayHUDEnabled, displayHUDEnabled, oldValue != displayHUDEnabled) } }
    @Published var soundHUDEnabled: Bool { didSet { persist(Keys.soundHUDEnabled, soundHUDEnabled, oldValue != soundHUDEnabled) } }
    /// Stateful OSD suppression (`OSDSuppressor`) — off by default, on-device-validated feature.
    @Stored("suppressSystemOSD", default: false) var suppressSystemOSD: Bool
    @Stored("hudShowMuteAsEmpty", default: true) var hudShowMuteAsEmpty: Bool
    @Stored("hudShowPercentageLabel", default: false) var hudShowPercentageLabel: Bool
    @Stored("hudShowOutputDevice", default: true) var hudShowOutputDevice: Bool
    /// Where the HUD renders: `.top` keeps it in the notch (unchanged prior
    /// behavior, and the default), any other `HUDPosition` routes it to the
    /// floating panel via `HUDPresenter`. Per-HUD placement (Sound vs.
    /// Display having independent positions) and a sync-with-notch toggle
    /// are deferred to a later task.
    @Stored("hudPosition", default: HUDPosition.top) var hudPosition: HUDPosition
    /// Seconds before the HUD auto-dismisses; UI constrains to 0.5...5, and
    /// `NotchViewModel.clampHUDDelay` clamps again at read time as a backstop.
    @Stored("hudHideDelay", default: 1.3) var hudHideDelay: Double
    /// MediaMate parity: when true, any external volume change (Control
    /// Center, headphones, another app) shows the HUD, not just media keys.
    @Stored("showOnExternalVolumeEvent", default: false) var showOnExternalVolumeEvent: Bool
    /// P2b: delegate EXTERNAL-display brightness writes to BetterDisplay/Lunar
    /// via `ExternalBrightnessBridge`. Off by default; UI disables the toggle
    /// when neither tool is detected.
    @Stored("externalBrightnessDelegate", default: false) var externalBrightnessDelegate: Bool
    @Published var fileTrayEnabled: Bool { didSet { persist(Keys.fileTrayEnabled, fileTrayEnabled, oldValue != fileTrayEnabled) } }
    @Published var todosEnabled: Bool { didSet { persist(Keys.todosEnabled, todosEnabled, oldValue != todosEnabled) } }

    // Goals
    @Published var goalsEnabled: Bool { didSet { persist(Keys.goalsEnabled, goalsEnabled, oldValue != goalsEnabled) } }
    @Published var claudeUsageEnabled: Bool { didSet { persist(Keys.claudeUsageEnabled, claudeUsageEnabled, oldValue != claudeUsageEnabled) } }
    @Published var statsEnabled: Bool { didSet { persist(Keys.statsEnabled, statsEnabled, oldValue != statsEnabled) } }
    @Published var currencyCode: String { didSet { persist(Keys.currencyCode, currencyCode, oldValue != currencyCode) } }
    @Published var currencySymbol: String { didSet { persist(Keys.currencySymbol, currencySymbol, oldValue != currencySymbol) } }

    // Battery
    @Published var batteryShowPercentage: Bool { didSet { persist(Keys.batteryShowPercentage, batteryShowPercentage, oldValue != batteryShowPercentage) } }
    @Published var batteryLowThreshold: Int { didSet { persist(Keys.batteryLowThreshold, batteryLowThreshold, oldValue != batteryLowThreshold) } }
    @Published var batteryNotifyCharged: Bool { didSet { persist(Keys.batteryNotifyCharged, batteryNotifyCharged, oldValue != batteryNotifyCharged) } }

    // Now Playing / media
    @Published var liveAudioVisualizer: Bool { didSet { persist(Keys.liveAudioVisualizer, liveAudioVisualizer, oldValue != liveAudioVisualizer) } }
    @Published var swipeToSeek: Bool { didSet { persist(Keys.swipeToSeek, swipeToSeek, oldValue != swipeToSeek) } }
    @Published var swipeGesturesEnabled: Bool { didSet { persist(Keys.swipeGesturesEnabled, swipeGesturesEnabled, oldValue != swipeGesturesEnabled) } }
    @Published var showTabBar: Bool { didSet { persist(Keys.showTabBar, showTabBar, oldValue != showTabBar) } }

    // Calendar
    @Published var calendarShowWeather: Bool { didSet { persist(Keys.calendarShowWeather, calendarShowWeather, oldValue != calendarShowWeather) } }
    @Published var calendarShowEvents: Bool { didSet { persist(Keys.calendarShowEvents, calendarShowEvents, oldValue != calendarShowEvents) } }

    // Stats
    @Published var statsRefreshSeconds: Double { didSet { persist(Keys.statsRefreshSeconds, statsRefreshSeconds, oldValue != statsRefreshSeconds) } }
    @Published var statsShowCPU: Bool { didSet { persist(Keys.statsShowCPU, statsShowCPU, oldValue != statsShowCPU) } }
    @Published var statsShowMemory: Bool { didSet { persist(Keys.statsShowMemory, statsShowMemory, oldValue != statsShowMemory) } }
    @Published var statsShowNetwork: Bool { didSet { persist(Keys.statsShowNetwork, statsShowNetwork, oldValue != statsShowNetwork) } }

    // Timer / Clipboard / Privacy
    @Published var timerSoundOnFinish: Bool { didSet { persist(Keys.timerSoundOnFinish, timerSoundOnFinish, oldValue != timerSoundOnFinish) } }
    @Published var clipboardEnabled: Bool { didSet { persist(Keys.clipboardEnabled, clipboardEnabled, oldValue != clipboardEnabled) } }
    @Published var clipboardHistorySize: Int { didSet { persist(Keys.clipboardHistorySize, clipboardHistorySize, oldValue != clipboardHistorySize) } }
    @Published var privacyIndicatorEnabled: Bool { didSet { persist(Keys.privacyIndicatorEnabled, privacyIndicatorEnabled, oldValue != privacyIndicatorEnabled) } }

    // Claude usage
    @Published var claudeCompactStyle: ClaudeCompactStyle { didSet { persist(Keys.claudeCompactStyle, claudeCompactStyle.rawValue, oldValue != claudeCompactStyle) } }
    @Published var claudeShowSession: Bool { didSet { persist(Keys.claudeShowSession, claudeShowSession, oldValue != claudeShowSession) } }
    @Published var claudeShowWeek: Bool { didSet { persist(Keys.claudeShowWeek, claudeShowWeek, oldValue != claudeShowWeek) } }
    @Published var claudeShowSpend: Bool { didSet { persist(Keys.claudeShowSpend, claudeShowSpend, oldValue != claudeShowSpend) } }
    @Published var claudeShowChart: Bool { didSet { persist(Keys.claudeShowChart, claudeShowChart, oldValue != claudeShowChart) } }
    @Published var claudeShowLegend: Bool { didSet { persist(Keys.claudeShowLegend, claudeShowLegend, oldValue != claudeShowLegend) } }
    @Published var claudeChartDays: Int { didSet { persist(Keys.claudeChartDays, claudeChartDays, oldValue != claudeChartDays) } }
    @Published var claudeChartCost: Bool { didSet { persist(Keys.claudeChartCost, claudeChartCost, oldValue != claudeChartCost) } }

    private var loading = false

    init(defaults: UserDefaults = .standard, kvs: KeyValueStore = NSUbiquitousKeyValueStore.default) {
        self.defaults = defaults
        self.kvs = kvs

        // Register defaults (all the Alcove-observed on/off states).
        defaults.register(defaults: [
            Keys.launchAtLogin: true,
            Keys.syncViaICloud: true,
            Keys.hideInFullscreen: false,   // stay visible over fullscreen by default
            Keys.collapseInFullscreen: true, // ...but rest bare there, so wings never cover content
            Keys.hideInMissionControl: true,
            Keys.hideFromScreenCapture: false,
            Keys.forceSimulatedNotch: false,
            Keys.simulatedDisplay: SimulatedDisplay.main.rawValue,
            Keys.idleActivity: NotchActivity.auto.rawValue,
            Keys.glassStyle: GlassStyle.clear.rawValue,
            Keys.glassIntensity: 0.5,
            Keys.idleMostRecent: false,
            Keys.forceEnableActivity: true,
            Keys.progressiveBlur: true,
            Keys.hapticFeedback: false,
            Keys.albumArtGlow: true,
            Keys.trackpadFeedbackEnabled: false,
            Keys.trackpadHapticsEnabled: true,
            Keys.trackpadSoundEnabled: true,
            Keys.trackpadFeedbackScroll: true,
            Keys.trackpadFeedbackClick: true,
            Keys.trackpadHapticStrength: HapticStrength.medium.rawValue,
            Keys.trackpadSoundVoice: FeedbackVoice.all[0].id,
            Keys.trackpadSoundVolume: 0.72,
            Keys.trackpadGesturesEnabled: true,
            Keys.batteryEnabled: true,
            Keys.connectivityEnabled: true,
            Keys.focusEnabled: true,
            Keys.displayHUDEnabled: true,
            Keys.soundHUDEnabled: true,
            Keys.fileTrayEnabled: true,
            Keys.todosEnabled: true,
            Keys.batteryShowPercentage: true,
            Keys.batteryLowThreshold: 20,
            Keys.batteryNotifyCharged: true,
            Keys.liveAudioVisualizer: true,
            Keys.swipeToSeek: true,
            Keys.swipeGesturesEnabled: true,
            Keys.showTabBar: true,
            Keys.calendarShowWeather: true,
            Keys.calendarShowEvents: true,
            Keys.statsRefreshSeconds: 2.0,
            Keys.statsShowCPU: true,
            Keys.statsShowMemory: true,
            Keys.statsShowNetwork: true,
            Keys.timerSoundOnFinish: true,
            Keys.clipboardEnabled: true,
            Keys.clipboardHistorySize: 20,
            Keys.privacyIndicatorEnabled: true,
            Keys.claudeCompactStyle: ClaudeCompactStyle.pie.rawValue,
            Keys.claudeShowSession: true,
            Keys.claudeShowWeek: true,
            Keys.claudeShowSpend: true,
            Keys.claudeShowChart: true,
            Keys.claudeShowLegend: true,
            Keys.claudeChartDays: 14,
            Keys.claudeChartCost: false,
            Keys.goalsEnabled: true,
            Keys.claudeUsageEnabled: true,
            Keys.statsEnabled: true,
            Keys.currencyCode: "GHS",
            Keys.currencySymbol: "₵",
        ])

        fileTrayEnabled = defaults.bool(forKey: Keys.fileTrayEnabled)
        todosEnabled = defaults.bool(forKey: Keys.todosEnabled)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        syncViaICloud = defaults.bool(forKey: Keys.syncViaICloud)
        hideInFullscreen = defaults.bool(forKey: Keys.hideInFullscreen)
        collapseInFullscreen = defaults.bool(forKey: Keys.collapseInFullscreen)
        hideInMissionControl = defaults.bool(forKey: Keys.hideInMissionControl)
        hideFromScreenCapture = defaults.bool(forKey: Keys.hideFromScreenCapture)
        forceSimulatedNotch = defaults.bool(forKey: Keys.forceSimulatedNotch)
        simulatedDisplay = SimulatedDisplay(rawValue: defaults.string(forKey: Keys.simulatedDisplay) ?? "") ?? .main
        idleActivity = NotchActivity(rawValue: defaults.string(forKey: Keys.idleActivity) ?? "") ?? .playing
        glassStyle = GlassStyle(rawValue: defaults.string(forKey: Keys.glassStyle) ?? "") ?? .clear
        glassIntensity = defaults.double(forKey: Keys.glassIntensity)
        idleMostRecent = defaults.bool(forKey: Keys.idleMostRecent)
        forceEnableActivity = defaults.bool(forKey: Keys.forceEnableActivity)
        progressiveBlur = defaults.bool(forKey: Keys.progressiveBlur)
        hapticFeedback = defaults.bool(forKey: Keys.hapticFeedback)
        albumArtGlow = defaults.bool(forKey: Keys.albumArtGlow)
        trackpadFeedbackEnabled = defaults.bool(forKey: Keys.trackpadFeedbackEnabled)
        trackpadHapticsEnabled = defaults.bool(forKey: Keys.trackpadHapticsEnabled)
        trackpadSoundEnabled = defaults.bool(forKey: Keys.trackpadSoundEnabled)
        trackpadFeedbackScroll = defaults.bool(forKey: Keys.trackpadFeedbackScroll)
        trackpadFeedbackClick = defaults.bool(forKey: Keys.trackpadFeedbackClick)
        trackpadHapticStrength = HapticStrength(rawValue: defaults.string(forKey: Keys.trackpadHapticStrength) ?? "") ?? .medium
        trackpadSoundVoice = defaults.string(forKey: Keys.trackpadSoundVoice) ?? FeedbackVoice.all[0].id
        trackpadSoundVolume = defaults.double(forKey: Keys.trackpadSoundVolume)
        trackpadGesturesEnabled = defaults.bool(forKey: Keys.trackpadGesturesEnabled)
        batteryEnabled = defaults.bool(forKey: Keys.batteryEnabled)
        connectivityEnabled = defaults.bool(forKey: Keys.connectivityEnabled)
        focusEnabled = defaults.bool(forKey: Keys.focusEnabled)
        displayHUDEnabled = defaults.bool(forKey: Keys.displayHUDEnabled)
        soundHUDEnabled = defaults.bool(forKey: Keys.soundHUDEnabled)
        batteryShowPercentage = defaults.bool(forKey: Keys.batteryShowPercentage)
        batteryLowThreshold = defaults.integer(forKey: Keys.batteryLowThreshold)
        batteryNotifyCharged = defaults.bool(forKey: Keys.batteryNotifyCharged)
        liveAudioVisualizer = defaults.bool(forKey: Keys.liveAudioVisualizer)
        swipeToSeek = defaults.bool(forKey: Keys.swipeToSeek)
        swipeGesturesEnabled = defaults.bool(forKey: Keys.swipeGesturesEnabled)
        showTabBar = defaults.bool(forKey: Keys.showTabBar)
        calendarShowWeather = defaults.bool(forKey: Keys.calendarShowWeather)
        calendarShowEvents = defaults.bool(forKey: Keys.calendarShowEvents)
        statsRefreshSeconds = defaults.double(forKey: Keys.statsRefreshSeconds)
        statsShowCPU = defaults.bool(forKey: Keys.statsShowCPU)
        statsShowMemory = defaults.bool(forKey: Keys.statsShowMemory)
        statsShowNetwork = defaults.bool(forKey: Keys.statsShowNetwork)
        timerSoundOnFinish = defaults.bool(forKey: Keys.timerSoundOnFinish)
        clipboardEnabled = defaults.bool(forKey: Keys.clipboardEnabled)
        clipboardHistorySize = defaults.integer(forKey: Keys.clipboardHistorySize)
        privacyIndicatorEnabled = defaults.bool(forKey: Keys.privacyIndicatorEnabled)
        claudeCompactStyle = ClaudeCompactStyle(rawValue: defaults.string(forKey: Keys.claudeCompactStyle) ?? "") ?? .pie
        claudeShowSession = defaults.bool(forKey: Keys.claudeShowSession)
        claudeShowWeek = defaults.bool(forKey: Keys.claudeShowWeek)
        claudeShowSpend = defaults.bool(forKey: Keys.claudeShowSpend)
        claudeShowChart = defaults.bool(forKey: Keys.claudeShowChart)
        claudeShowLegend = defaults.bool(forKey: Keys.claudeShowLegend)
        claudeChartDays = defaults.integer(forKey: Keys.claudeChartDays)
        claudeChartCost = defaults.bool(forKey: Keys.claudeChartCost)
        goalsEnabled = defaults.bool(forKey: Keys.goalsEnabled)
        claudeUsageEnabled = defaults.bool(forKey: Keys.claudeUsageEnabled)
        statsEnabled = defaults.bool(forKey: Keys.statsEnabled)
        currencyCode = defaults.string(forKey: Keys.currencyCode) ?? "GHS"
        currencySymbol = defaults.string(forKey: Keys.currencySymbol) ?? "₵"

        NotificationCenter.default.addObserver(
            self, selector: #selector(cloudChanged(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud
        )
        if syncViaICloud { cloud.synchronize() }
    }

    private var cloudSyncPending = false

    /// Writes a single changed key to `UserDefaults` (and, when enabled, the
    /// iCloud KVS). Only the one key that changed is written — a slider drag no
    /// longer rewrites all ~50 keys per tick — and `cloud.synchronize()` is
    /// coalesced to at most once per runloop turn.
    private func persist(_ key: String, _ value: Any, _ changed: Bool) {
        guard !loading, changed else { return }
        defaults.set(value, forKey: key)
        guard syncViaICloud else { return }
        cloud.set(value, forKey: key)
        scheduleCloudSync()
    }

    private func scheduleCloudSync() {
        guard !cloudSyncPending else { return }
        cloudSyncPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cloudSyncPending = false
            self.cloud.synchronize()
        }
    }

    /// Inbound iCloud change (a write from another Mac): mirror every key back
    /// into the published properties — the inverse of `persist`. `loading` is
    /// held so the `didSet` observers don't echo the values straight back out.
    @objc private func cloudChanged(_ note: Notification) {
        guard syncViaICloud else { return }
        Task { @MainActor in
            loading = true
            defer { loading = false }
            // Nothing has synced yet if even the sentinel key is absent.
            guard cloud.object(forKey: Keys.launchAtLogin) != nil else { return }

            // Only apply keys that actually exist in iCloud — a store that was
            // written by an older/newer build (or mid-migration) can be missing
            // keys, and reading an absent key returns 0/false, which would
            // silently flip toggles off on every external change.
            pullBool(Keys.launchAtLogin) { launchAtLogin = $0 }
            pullBool(Keys.syncViaICloud) { syncViaICloud = $0 }
            pullBool(Keys.hideInFullscreen) { hideInFullscreen = $0 }
            pullBool(Keys.collapseInFullscreen) { collapseInFullscreen = $0 }
            pullBool(Keys.hideInMissionControl) { hideInMissionControl = $0 }
            pullBool(Keys.hideFromScreenCapture) { hideFromScreenCapture = $0 }
            pullBool(Keys.forceSimulatedNotch) { forceSimulatedNotch = $0 }
            pullString(Keys.simulatedDisplay) { simulatedDisplay = SimulatedDisplay(rawValue: $0) ?? simulatedDisplay }
            pullString(Keys.idleActivity) { idleActivity = NotchActivity(rawValue: $0) ?? idleActivity }
            pullString(Keys.glassStyle) { glassStyle = GlassStyle(rawValue: $0) ?? glassStyle }
            pullDouble(Keys.glassIntensity) { glassIntensity = $0 }
            pullBool(Keys.idleMostRecent) { idleMostRecent = $0 }
            pullBool(Keys.forceEnableActivity) { forceEnableActivity = $0 }
            pullBool(Keys.progressiveBlur) { progressiveBlur = $0 }
            pullBool(Keys.hapticFeedback) { hapticFeedback = $0 }
            pullBool(Keys.albumArtGlow) { albumArtGlow = $0 }
            pullBool(Keys.trackpadFeedbackEnabled) { trackpadFeedbackEnabled = $0 }
            pullBool(Keys.trackpadHapticsEnabled) { trackpadHapticsEnabled = $0 }
            pullBool(Keys.trackpadSoundEnabled) { trackpadSoundEnabled = $0 }
            pullBool(Keys.trackpadFeedbackScroll) { trackpadFeedbackScroll = $0 }
            pullBool(Keys.trackpadFeedbackClick) { trackpadFeedbackClick = $0 }
            pullString(Keys.trackpadHapticStrength) { trackpadHapticStrength = HapticStrength(rawValue: $0) ?? trackpadHapticStrength }
            pullString(Keys.trackpadSoundVoice) { trackpadSoundVoice = $0 }
            pullDouble(Keys.trackpadSoundVolume) { trackpadSoundVolume = $0 }
            pullBool(Keys.trackpadGesturesEnabled) { trackpadGesturesEnabled = $0 }
            pullBool(Keys.batteryEnabled) { batteryEnabled = $0 }
            pullBool(Keys.connectivityEnabled) { connectivityEnabled = $0 }
            pullBool(Keys.focusEnabled) { focusEnabled = $0 }
            pullBool(Keys.displayHUDEnabled) { displayHUDEnabled = $0 }
            pullBool(Keys.soundHUDEnabled) { soundHUDEnabled = $0 }
            pullBool(Keys.fileTrayEnabled) { fileTrayEnabled = $0 }
            pullBool(Keys.todosEnabled) { todosEnabled = $0 }
            pullBool(Keys.batteryShowPercentage) { batteryShowPercentage = $0 }
            pullInt(Keys.batteryLowThreshold) { batteryLowThreshold = $0 }
            pullBool(Keys.batteryNotifyCharged) { batteryNotifyCharged = $0 }
            pullBool(Keys.liveAudioVisualizer) { liveAudioVisualizer = $0 }
            pullBool(Keys.swipeToSeek) { swipeToSeek = $0 }
            pullBool(Keys.swipeGesturesEnabled) { swipeGesturesEnabled = $0 }
            pullBool(Keys.showTabBar) { showTabBar = $0 }
            pullBool(Keys.calendarShowWeather) { calendarShowWeather = $0 }
            pullBool(Keys.calendarShowEvents) { calendarShowEvents = $0 }
            pullDouble(Keys.statsRefreshSeconds) { statsRefreshSeconds = $0 }
            pullBool(Keys.statsShowCPU) { statsShowCPU = $0 }
            pullBool(Keys.statsShowMemory) { statsShowMemory = $0 }
            pullBool(Keys.statsShowNetwork) { statsShowNetwork = $0 }
            pullBool(Keys.timerSoundOnFinish) { timerSoundOnFinish = $0 }
            pullBool(Keys.clipboardEnabled) { clipboardEnabled = $0 }
            pullInt(Keys.clipboardHistorySize) { clipboardHistorySize = $0 }
            pullBool(Keys.privacyIndicatorEnabled) { privacyIndicatorEnabled = $0 }
            pullString(Keys.claudeCompactStyle) { claudeCompactStyle = ClaudeCompactStyle(rawValue: $0) ?? claudeCompactStyle }
            pullBool(Keys.claudeShowSession) { claudeShowSession = $0 }
            pullBool(Keys.claudeShowWeek) { claudeShowWeek = $0 }
            pullBool(Keys.claudeShowSpend) { claudeShowSpend = $0 }
            pullBool(Keys.claudeShowChart) { claudeShowChart = $0 }
            pullBool(Keys.claudeShowLegend) { claudeShowLegend = $0 }
            pullInt(Keys.claudeChartDays) { claudeChartDays = $0 }
            pullBool(Keys.claudeChartCost) { claudeChartCost = $0 }
        }
    }

    // Per-key pulls that no-op when the key is absent from iCloud.
    private func pullBool(_ key: String, _ apply: (Bool) -> Void) {
        if cloud.object(forKey: key) != nil { apply(cloud.bool(forKey: key)) }
    }
    private func pullInt(_ key: String, _ apply: (Int) -> Void) {
        if cloud.object(forKey: key) != nil { apply(Int(cloud.longLong(forKey: key))) }
    }
    private func pullDouble(_ key: String, _ apply: (Double) -> Void) {
        if cloud.object(forKey: key) != nil { apply(cloud.double(forKey: key)) }
    }
    private func pullString(_ key: String, _ apply: (String) -> Void) {
        if let s = cloud.string(forKey: key) { apply(s) }
    }

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let syncViaICloud = "syncViaICloud"
        static let hideInFullscreen = "hideInFullscreen"
        static let collapseInFullscreen = "collapseInFullscreen"
        static let hideInMissionControl = "hideInMissionControl"
        static let hideFromScreenCapture = "hideFromScreenCapture"
        static let forceSimulatedNotch = "forceSimulatedNotch"
        static let simulatedDisplay = "simulatedDisplay"
        static let idleActivity = "idleActivity"
        static let glassStyle = "glassStyle"
        static let glassIntensity = "glassIntensity"
        static let idleMostRecent = "idleMostRecent"
        static let forceEnableActivity = "forceEnableActivity"
        static let progressiveBlur = "progressiveBlur"
        static let hapticFeedback = "hapticFeedback"
        static let albumArtGlow = "albumArtGlow"
        static let trackpadFeedbackEnabled = "trackpadFeedbackEnabled"
        static let trackpadHapticsEnabled = "trackpadHapticsEnabled"
        static let trackpadSoundEnabled = "trackpadSoundEnabled"
        static let trackpadFeedbackScroll = "trackpadFeedbackScroll"
        static let trackpadFeedbackClick = "trackpadFeedbackClick"
        static let trackpadHapticStrength = "trackpadHapticStrength"
        static let trackpadSoundVoice = "trackpadSoundVoice"
        static let trackpadSoundVolume = "trackpadSoundVolume"
        static let trackpadGesturesEnabled = "trackpadGesturesEnabled"
        static let batteryEnabled = "batteryEnabled"
        static let connectivityEnabled = "connectivityEnabled"
        static let focusEnabled = "focusEnabled"
        static let displayHUDEnabled = "displayHUDEnabled"
        static let soundHUDEnabled = "soundHUDEnabled"
        static let fileTrayEnabled = "fileTrayEnabled"
        static let todosEnabled = "todosEnabled"
        static let batteryShowPercentage = "batteryShowPercentage"
        static let batteryLowThreshold = "batteryLowThreshold"
        static let batteryNotifyCharged = "batteryNotifyCharged"
        static let liveAudioVisualizer = "liveAudioVisualizer"
        static let swipeToSeek = "swipeToSeek"
        static let swipeGesturesEnabled = "swipeGesturesEnabled"
        static let showTabBar = "showTabBar"
        static let calendarShowWeather = "calendarShowWeather"
        static let calendarShowEvents = "calendarShowEvents"
        static let statsRefreshSeconds = "statsRefreshSeconds"
        static let statsShowCPU = "statsShowCPU"
        static let statsShowMemory = "statsShowMemory"
        static let statsShowNetwork = "statsShowNetwork"
        static let timerSoundOnFinish = "timerSoundOnFinish"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardHistorySize = "clipboardHistorySize"
        static let privacyIndicatorEnabled = "privacyIndicatorEnabled"
        static let claudeCompactStyle = "claudeCompactStyle"
        static let claudeShowSession = "claudeShowSession"
        static let claudeShowWeek = "claudeShowWeek"
        static let claudeShowSpend = "claudeShowSpend"
        static let claudeShowChart = "claudeShowChart"
        static let claudeShowLegend = "claudeShowLegend"
        static let claudeChartDays = "claudeChartDays"
        static let claudeChartCost = "claudeChartCost"
        static let goalsEnabled = "goalsEnabled"
        static let claudeUsageEnabled = "claudeUsageEnabled"
        static let statsEnabled = "statsEnabled"
        static let currencyCode = "currencyCode"
        static let currencySymbol = "currencySymbol"
    }
}
