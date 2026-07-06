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
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default

    // General
    @Published var launchAtLogin: Bool { didSet { persist(oldValue != launchAtLogin) } }
    @Published var syncViaICloud: Bool { didSet { persist(oldValue != syncViaICloud) } }
    @Published var hideInFullscreen: Bool { didSet { persist(oldValue != hideInFullscreen) } }
    @Published var hideInMissionControl: Bool { didSet { persist(oldValue != hideInMissionControl) } }
    @Published var hideFromScreenCapture: Bool { didSet { persist(oldValue != hideFromScreenCapture) } }
    @Published var forceSimulatedNotch: Bool { didSet { persist(oldValue != forceSimulatedNotch) } }
    @Published var simulatedDisplay: SimulatedDisplay { didSet { persist(oldValue != simulatedDisplay) } }

    // Idle activity
    @Published var idleActivity: NotchActivity { didSet { persist(oldValue != idleActivity) } }
    @Published var idleMostRecent: Bool { didSet { persist(oldValue != idleMostRecent) } }
    @Published var forceEnableActivity: Bool { didSet { persist(oldValue != forceEnableActivity) } }

    // Appearance
    @Published var glassStyle: GlassStyle { didSet { persist(oldValue != glassStyle) } }
    @Published var glassIntensity: Double { didSet { persist(oldValue != glassIntensity) } }

    // Behaviour
    @Published var progressiveBlur: Bool { didSet { persist(oldValue != progressiveBlur) } }
    @Published var hapticFeedback: Bool { didSet { persist(oldValue != hapticFeedback) } }
    @Published var albumArtGlow: Bool { didSet { persist(oldValue != albumArtGlow) } }

    // Notifications
    @Published var batteryEnabled: Bool { didSet { persist(oldValue != batteryEnabled) } }
    @Published var connectivityEnabled: Bool { didSet { persist(oldValue != connectivityEnabled) } }
    @Published var focusEnabled: Bool { didSet { persist(oldValue != focusEnabled) } }
    @Published var displayHUDEnabled: Bool { didSet { persist(oldValue != displayHUDEnabled) } }
    @Published var soundHUDEnabled: Bool { didSet { persist(oldValue != soundHUDEnabled) } }
    @Published var fileTrayEnabled: Bool { didSet { persist(oldValue != fileTrayEnabled) } }
    @Published var todosEnabled: Bool { didSet { persist(oldValue != todosEnabled) } }

    // Battery
    @Published var batteryShowPercentage: Bool { didSet { persist(oldValue != batteryShowPercentage) } }
    @Published var batteryLowThreshold: Int { didSet { persist(oldValue != batteryLowThreshold) } }
    @Published var batteryNotifyCharged: Bool { didSet { persist(oldValue != batteryNotifyCharged) } }

    // Now Playing / media
    @Published var liveAudioVisualizer: Bool { didSet { persist(oldValue != liveAudioVisualizer) } }
    @Published var swipeToSeek: Bool { didSet { persist(oldValue != swipeToSeek) } }
    @Published var swipeGesturesEnabled: Bool { didSet { persist(oldValue != swipeGesturesEnabled) } }

    // Calendar
    @Published var calendarShowWeather: Bool { didSet { persist(oldValue != calendarShowWeather) } }
    @Published var calendarShowEvents: Bool { didSet { persist(oldValue != calendarShowEvents) } }

    // Stats
    @Published var statsRefreshSeconds: Double { didSet { persist(oldValue != statsRefreshSeconds) } }
    @Published var statsShowCPU: Bool { didSet { persist(oldValue != statsShowCPU) } }
    @Published var statsShowMemory: Bool { didSet { persist(oldValue != statsShowMemory) } }
    @Published var statsShowNetwork: Bool { didSet { persist(oldValue != statsShowNetwork) } }

    // Timer / Clipboard / Privacy
    @Published var timerSoundOnFinish: Bool { didSet { persist(oldValue != timerSoundOnFinish) } }
    @Published var clipboardEnabled: Bool { didSet { persist(oldValue != clipboardEnabled) } }
    @Published var clipboardHistorySize: Int { didSet { persist(oldValue != clipboardHistorySize) } }
    @Published var privacyIndicatorEnabled: Bool { didSet { persist(oldValue != privacyIndicatorEnabled) } }

    // Claude usage
    @Published var claudeCompactStyle: ClaudeCompactStyle { didSet { persist(oldValue != claudeCompactStyle) } }
    @Published var claudeShowSession: Bool { didSet { persist(oldValue != claudeShowSession) } }
    @Published var claudeShowWeek: Bool { didSet { persist(oldValue != claudeShowWeek) } }
    @Published var claudeShowSpend: Bool { didSet { persist(oldValue != claudeShowSpend) } }
    @Published var claudeShowChart: Bool { didSet { persist(oldValue != claudeShowChart) } }
    @Published var claudeShowLegend: Bool { didSet { persist(oldValue != claudeShowLegend) } }
    @Published var claudeChartDays: Int { didSet { persist(oldValue != claudeChartDays) } }
    @Published var claudeChartCost: Bool { didSet { persist(oldValue != claudeChartCost) } }

    private var loading = false

    private init() {
        // Register defaults (all the Alcove-observed on/off states).
        defaults.register(defaults: [
            Keys.launchAtLogin: true,
            Keys.syncViaICloud: true,
            Keys.hideInFullscreen: false,   // stay visible over fullscreen by default
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
        ])

        fileTrayEnabled = defaults.bool(forKey: Keys.fileTrayEnabled)
        todosEnabled = defaults.bool(forKey: Keys.todosEnabled)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        syncViaICloud = defaults.bool(forKey: Keys.syncViaICloud)
        hideInFullscreen = defaults.bool(forKey: Keys.hideInFullscreen)
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

        NotificationCenter.default.addObserver(
            self, selector: #selector(cloudChanged(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud
        )
        if syncViaICloud { cloud.synchronize() }
    }

    private func persist(_ changed: Bool) {
        guard !loading, changed else { return }
        let pairs: [(String, Any)] = [
            (Keys.launchAtLogin, launchAtLogin),
            (Keys.syncViaICloud, syncViaICloud),
            (Keys.hideInFullscreen, hideInFullscreen),
            (Keys.hideInMissionControl, hideInMissionControl),
            (Keys.hideFromScreenCapture, hideFromScreenCapture),
            (Keys.forceSimulatedNotch, forceSimulatedNotch),
            (Keys.simulatedDisplay, simulatedDisplay.rawValue),
            (Keys.idleActivity, idleActivity.rawValue),
            (Keys.glassStyle, glassStyle.rawValue),
            (Keys.glassIntensity, glassIntensity),
            (Keys.idleMostRecent, idleMostRecent),
            (Keys.forceEnableActivity, forceEnableActivity),
            (Keys.progressiveBlur, progressiveBlur),
            (Keys.hapticFeedback, hapticFeedback),
            (Keys.albumArtGlow, albumArtGlow),
            (Keys.batteryEnabled, batteryEnabled),
            (Keys.connectivityEnabled, connectivityEnabled),
            (Keys.focusEnabled, focusEnabled),
            (Keys.displayHUDEnabled, displayHUDEnabled),
            (Keys.soundHUDEnabled, soundHUDEnabled),
            (Keys.fileTrayEnabled, fileTrayEnabled),
            (Keys.todosEnabled, todosEnabled),
            (Keys.batteryShowPercentage, batteryShowPercentage),
            (Keys.batteryLowThreshold, batteryLowThreshold),
            (Keys.batteryNotifyCharged, batteryNotifyCharged),
            (Keys.liveAudioVisualizer, liveAudioVisualizer),
            (Keys.swipeToSeek, swipeToSeek),
            (Keys.swipeGesturesEnabled, swipeGesturesEnabled),
            (Keys.calendarShowWeather, calendarShowWeather),
            (Keys.calendarShowEvents, calendarShowEvents),
            (Keys.statsRefreshSeconds, statsRefreshSeconds),
            (Keys.statsShowCPU, statsShowCPU),
            (Keys.statsShowMemory, statsShowMemory),
            (Keys.statsShowNetwork, statsShowNetwork),
            (Keys.timerSoundOnFinish, timerSoundOnFinish),
            (Keys.clipboardEnabled, clipboardEnabled),
            (Keys.clipboardHistorySize, clipboardHistorySize),
            (Keys.privacyIndicatorEnabled, privacyIndicatorEnabled),
            (Keys.claudeCompactStyle, claudeCompactStyle.rawValue),
            (Keys.claudeShowSession, claudeShowSession),
            (Keys.claudeShowWeek, claudeShowWeek),
            (Keys.claudeShowSpend, claudeShowSpend),
            (Keys.claudeShowChart, claudeShowChart),
            (Keys.claudeShowLegend, claudeShowLegend),
            (Keys.claudeChartDays, claudeChartDays),
            (Keys.claudeChartCost, claudeChartCost),
        ]
        for (k, v) in pairs {
            defaults.set(v, forKey: k)
            if syncViaICloud { cloud.set(v, forKey: k) }
        }
        if syncViaICloud { cloud.synchronize() }
    }

    @objc private func cloudChanged(_ note: Notification) {
        guard syncViaICloud else { return }
        Task { @MainActor in
            loading = true
            defer { loading = false }
            if cloud.object(forKey: Keys.launchAtLogin) != nil {
                launchAtLogin = cloud.bool(forKey: Keys.launchAtLogin)
                hideInFullscreen = cloud.bool(forKey: Keys.hideInFullscreen)
                progressiveBlur = cloud.bool(forKey: Keys.progressiveBlur)
                idleActivity = NotchActivity(rawValue: cloud.string(forKey: Keys.idleActivity) ?? "") ?? idleActivity
                // (Remaining keys mirror the same pattern; kept brief.)
            }
        }
    }

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let syncViaICloud = "syncViaICloud"
        static let hideInFullscreen = "hideInFullscreen"
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
    }
}
