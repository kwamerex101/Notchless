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
        case .tasks: return .yellow
        case .privacyDot: return .green
        case .goals: return .pink
        case .meetings: return .cyan
        case .permissions: return .blue
        case .about: return .gray
        }
    }

    var comingSoon: Bool { false }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var meeting: MeetingController
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                row(.general)
                Section("Notifications") {
                    ForEach([SettingsSection.battery, .connectivity, .focus, .display, .sound]) { row($0) }
                }
                Section("Live Activities") {
                    ForEach([SettingsSection.nowPlaying, .calendar, .fileTray, .dictation,
                             .stats, .claudeStats, .timer, .clipboard, .tasks, .privacyDot, .goals,
                             .meetings]) { row($0) }
                }
                Section("Notchless") {
                    ForEach([SettingsSection.permissions, .about]) { row($0) }
                }
            }
            .navigationSplitViewColumnWidth(220)
        } detail: {
            ScrollView {
                content
                    .environment(\.paneTint, selection.tint)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ section: SettingsSection) -> some View {
        Label {
            HStack {
                Text(section.title)
                if section.comingSoon {
                    Text("Soon")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
            }
        } icon: {
            Image(systemName: section.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    section.tint.opacity(0.92),
                                    section.tint,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
        }
        .tag(section)
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
                    .font(.callout).foregroundStyle(.secondary)
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
        HStack(spacing: 8) {
            Image(systemName: section.systemImage).foregroundStyle(section.tint)
            Text(section.title).font(.title2.bold())
        }
    }
}
