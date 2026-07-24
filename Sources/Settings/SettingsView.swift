import SwiftUI

/// Sidebar destinations, mirroring Alcove's settings layout (PLAN.md §1.2).
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case battery, connectivity, focus, display, sound
    case nowPlaying, calendar, fileTray, dictation, stats, claudeStats, timer, clipboard, tasks, privacyDot, goals
    case meetings
    case permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .battery: return "Battery"
        case .connectivity: return "Connectivity"
        case .focus: return "Focus"
        case .display: return "Display"
        case .sound: return "Sound"
        case .nowPlaying: return "Now Playing"
        case .calendar: return "Calendar"
        case .fileTray: return "File Tray"
        case .dictation: return "Dictation"
        case .stats: return "System Stats"
        case .claudeStats: return "Claude Usage"
        case .timer: return "Timer"
        case .clipboard: return "Clipboard"
        case .tasks: return "Tasks"
        case .privacyDot: return "Privacy"
        case .goals: return "Goals"
        case .meetings: return "Meetings"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .battery: return "bolt.fill"
        case .connectivity: return "headphones"
        case .focus: return "moon.fill"
        case .display: return "sun.max.fill"
        case .sound: return "speaker.wave.2.fill"
        case .nowPlaying: return "play.circle.fill"
        case .calendar: return "calendar"
        case .fileTray: return "tray.fill"
        case .dictation: return "mic.fill"
        case .stats: return "cpu"
        case .claudeStats: return "chart.pie.fill"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard.fill"
        case .tasks: return "checklist"
        case .privacyDot: return "checkmark.shield.fill"
        case .goals: return "target"
        case .meetings: return "person.2.wave.2.fill"
        case .permissions: return "hand.raised.fill"
        case .about: return "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .battery: return .orange
        case .connectivity: return .green
        case .focus: return .indigo
        case .display: return .purple
        case .sound: return .purple
        case .nowPlaying: return .red
        case .calendar: return .red
        case .fileTray: return .gray
        case .dictation: return .teal
        case .stats: return .green
        case .claudeStats: return .orange
        case .timer: return .orange
        case .clipboard: return .indigo
        // A deep amber rather than flat yellow — legible as a tinted label on a
        // light card and behind white text on the selected segmented tile.
        case .tasks: return Color(red: 0.78, green: 0.53, blue: 0.04)
        case .privacyDot: return .green
        case .goals: return .pink
        case .meetings: return .cyan
        case .permissions: return .blue
        case .about: return .gray
        }
    }

    var description: String {
        switch self {
        case .general: return "Startup, appearance, and system-wide behaviour."
        case .battery: return "Charge, low-battery, and full-charge alerts."
        case .connectivity: return "Bluetooth and audio-device connection alerts."
        case .focus: return "Focus / Do Not Disturb change alerts."
        case .display: return "A brightness HUD when you change display brightness."
        case .sound: return "A volume HUD when you change output volume."
        case .nowPlaying: return "Live media controls and artwork for what's playing."
        case .calendar: return "Your next event, glanceable in the notch."
        case .fileTray: return "Drag files onto the notch to hold and move them."
        case .dictation: return "Speak anywhere; text appears where you type."
        case .stats: return "Live CPU, memory, and network in the notch."
        case .claudeStats: return "Your Claude usage and limits at a glance."
        case .timer: return "Quick countdowns that live in the notch."
        case .clipboard: return "Recent clipboard items, ready to paste."
        case .tasks: return "A lightweight to-do list in the notch."
        case .privacyDot: return "A dot when the mic or camera is in use."
        case .goals: return "Track daily goals and progress rings."
        case .meetings: return "Capture and transcribe meetings on device."
        case .permissions: return "Grant the system access Notchless needs."
        case .about: return "Version, credits, and updates."
        }
    }

    var comingSoon: Bool { false }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var meeting: MeetingController
    @State private var selection: SettingsSection

    /// `initialSelection` is a debug-harness seam (see `DebugStateDump`) so a
    /// caller outside this file can render a specific pane — the sidebar
    /// itself still owns `selection` via normal `@State` after that.
    init(settings: SettingsStore, meeting: MeetingController, initialSelection: SettingsSection = .general) {
        self.settings = settings
        self.meeting = meeting
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                content
                    .environment(\.paneTint, selection.tint)
                    .padding(.horizontal, 26).padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(SettingsTheme.windowBody)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Monochrome sidebar (spec §5): no colored icon chips, selection is the
    /// only highlight. Top padding leaves room for the window's own traffic
    /// lights, which sit inside this dark surface.
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Color.clear.frame(height: 26) // room for traffic lights
                row(.general)
                sectionHeader("Notifications")
                ForEach([SettingsSection.battery, .connectivity, .focus, .display, .sound]) { row($0) }
                sectionHeader("Live Activities")
                ForEach([SettingsSection.nowPlaying, .calendar, .fileTray, .dictation,
                         .stats, .claudeStats, .timer, .clipboard, .tasks, .privacyDot, .goals,
                         .meetings]) { row($0) }
                sectionHeader("Notchless")
                ForEach([SettingsSection.permissions, .about]) { row($0) }
            }
            .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 14)
        }
        .frame(width: 212)
        .background(SettingsTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(SettingsTheme.sidebarBorder).frame(width: 1)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(SettingsTheme.sidebarHeader)
            .padding(.horizontal, 8)
            .padding(.top, 16).padding(.bottom, 4)
    }

    private func row(_ section: SettingsSection) -> some View {
        let selected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 13, height: 13)
                Text(section.title)
                    .font(.system(size: 12, weight: .medium))
                if section.comingSoon {
                    Text("Soon")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? SettingsTheme.text : SettingsTheme.textMuted)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? SettingsTheme.sidebarSelected : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch selection {
        case .general: GeneralPane(settings: settings)
        case .battery: BatteryPane(settings: settings)
        case .connectivity: ConnectivityPane(settings: settings)
        case .focus: FocusPane(settings: settings)
        case .display: DisplayPane(settings: settings)
        case .sound: SoundPane(settings: settings)
        case .nowPlaying: NowPlayingPane(settings: settings)
        case .calendar: CalendarPane(settings: settings)
        case .stats: StatsPane(settings: settings)
        case .claudeStats: ClaudeStatsPane(settings: settings)
        case .timer: TimerPane(settings: settings)
        case .clipboard: ClipboardPane(settings: settings)
        case .tasks: TodosPane(settings: settings)
        case .privacyDot: PrivacyPane(settings: settings)
        case .goals: GoalsPane(settings: settings)
        case .dictation: DictationPane()
        case .meetings: MeetingsPane(meeting: meeting)
        case .permissions: PermissionsPane()
        default: PlaceholderPane(section: selection, settings: settings)
        }
    }
}

/// Panes not yet fleshed out get a titled placeholder with any relevant toggle.
struct PlaceholderPane: View {
    let section: SettingsSection
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: section)
            switch section {
            case .battery: ToggleCard(title: "Battery notifications", isOn: $settings.batteryEnabled)
            case .connectivity: ToggleCard(title: "Connectivity notifications", isOn: $settings.connectivityEnabled)
            case .focus: ToggleCard(title: "Focus notifications", isOn: $settings.focusEnabled)
            case .display: ToggleCard(title: "Display HUD", isOn: $settings.displayHUDEnabled)
            case .sound: ToggleCard(title: "Sound HUD", isOn: $settings.soundHUDEnabled)
            case .nowPlaying: ToggleCard(title: "Album art color glow", isOn: $settings.albumArtGlow)
            case .fileTray:
                ToggleCard(title: "File Tray", isOn: $settings.fileTrayEnabled)
                Text("Drag files onto the notch to hold them, then drag them back out anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            case .about:
                AboutPane()
            default:
                Text("Configuration for \(section.title) coming soon.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct PaneHeader: View {
    let section: SettingsSection
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: section.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SettingsTheme.text)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SettingsTheme.iconChip)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.system(size: 17, weight: .bold)).foregroundStyle(SettingsTheme.text)
                Text(section.description).font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
