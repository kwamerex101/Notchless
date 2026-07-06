import SwiftUI

// MARK: - Battery

struct BatteryPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .battery)
            SectionLabel("Notch")
            CardGroup {
                ToggleRow(title: "Show battery activity", isOn: $settings.batteryEnabled)
                Divider()
                ToggleRow(title: "Show percentage", isOn: $settings.batteryShowPercentage)
            }
            SectionLabel("Alerts")
            CardGroup {
                HStack {
                    Text("Low battery at")
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(settings.batteryLowThreshold) },
                        set: { settings.batteryLowThreshold = Int($0) }
                    ), in: 5...50, step: 5).frame(width: 150)
                    Text("\(settings.batteryLowThreshold)%").frame(width: 44, alignment: .trailing)
                }
                Divider()
                ToggleRow(title: "Notify when fully charged", isOn: $settings.batteryNotifyCharged)
            }
            Spacer()
        }
    }
}

// MARK: - Connectivity / Focus / Display / Sound (notification toggles)

struct ConnectivityPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .connectivity)
            CardGroup {
                ToggleRow(title: "Connectivity notifications", isOn: $settings.connectivityEnabled)
            }
            Text("Shows a notch banner when AirPods or other audio devices connect or disconnect.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

struct FocusPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .focus)
            CardGroup {
                ToggleRow(title: "Focus notifications", isOn: $settings.focusEnabled)
            }
            Text("Announces Focus mode changes (Do Not Disturb, Work, Sleep…) in the notch.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

struct DisplayPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .display)
            CardGroup {
                ToggleRow(title: "Brightness HUD", isOn: $settings.displayHUDEnabled)
            }
            Text("Replaces the system brightness overlay with one anchored to the notch.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

struct SoundPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .sound)
            CardGroup {
                ToggleRow(title: "Volume HUD", isOn: $settings.soundHUDEnabled)
            }
            Text("Replaces the system volume overlay with one anchored to the notch.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Now Playing

struct NowPlayingPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .nowPlaying)
            SectionLabel("Visualizer")
            CardGroup {
                ToggleRow(title: "Album art colour glow", isOn: $settings.albumArtGlow)
                Divider()
                ToggleRow(title: "Live audio visualizer", isOn: $settings.liveAudioVisualizer)
                Text("Reacts to real system audio (needs the audio-recording permission). Off uses a decorative animation.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SectionLabel("Gestures")
            CardGroup {
                ToggleRow(title: "Swipe to seek", isOn: $settings.swipeToSeek)
                Text("Two-finger swipe left/right on the notch scrubs the current track ±10s.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

// MARK: - Calendar

struct CalendarPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .calendar)
            CardGroup {
                ToggleRow(title: "Show upcoming events", isOn: $settings.calendarShowEvents)
                Divider()
                ToggleRow(title: "Show weather", isOn: $settings.calendarShowWeather)
            }
            Spacer()
        }
    }
}

// MARK: - Stats

struct StatsPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .stats)
            SectionLabel("Metrics")
            CardGroup {
                ToggleRow(title: "CPU", isOn: $settings.statsShowCPU)
                Divider()
                ToggleRow(title: "Memory", isOn: $settings.statsShowMemory)
                Divider()
                ToggleRow(title: "Network", isOn: $settings.statsShowNetwork)
            }
            SectionLabel("Refresh")
            CardGroup {
                HStack {
                    Text("Update every")
                    Spacer()
                    Slider(value: $settings.statsRefreshSeconds, in: 1...10, step: 1).frame(width: 150)
                    Text("\(Int(settings.statsRefreshSeconds))s").frame(width: 40, alignment: .trailing)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Claude usage

struct ClaudeStatsPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .claudeStats)

            SectionLabel("Compact notch")
            CardGroup {
                LabeledRow("Show") {
                    SettingsPicker(options: ClaudeCompactStyle.allCases, selection: $settings.claudeCompactStyle) { $0.title }
                }
            }

            SectionLabel("Expanded view")
            CardGroup {
                ToggleRow(title: "Session (5-hour)", isOn: $settings.claudeShowSession)
                Divider()
                ToggleRow(title: "This week", isOn: $settings.claudeShowWeek)
                Divider()
                ToggleRow(title: "Daily spend", isOn: $settings.claudeShowSpend)
                Divider()
                ToggleRow(title: "Usage chart", isOn: $settings.claudeShowChart)
                Divider()
                ToggleRow(title: "Token breakdown", isOn: $settings.claudeShowLegend)
            }

            if settings.claudeShowChart {
                SectionLabel("Chart")
                CardGroup {
                    LabeledRow("Window") {
                        SettingsPicker(options: [7, 14, 30], selection: $settings.claudeChartDays) { "\($0) days" }
                    }
                    Divider()
                    LabeledRow("Plot") {
                        SettingsPicker(options: [false, true], selection: $settings.claudeChartCost) { $0 ? "Cost" : "Tokens" }
                    }
                }
            }

            Text("Estimated from local Claude Code transcripts (tokens × model pricing); refreshes every 10 minutes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Timer

struct TimerPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .timer)
            CardGroup {
                ToggleRow(title: "Chime when finished", isOn: $settings.timerSoundOnFinish)
            }
            Text("Start a timer from the notch: set the idle activity to Timer, or expand the notch to pick a preset.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Clipboard

struct ClipboardPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .clipboard)
            CardGroup {
                ToggleRow(title: "Remember clipboard history", isOn: $settings.clipboardEnabled)
                Divider()
                HStack {
                    Text("Keep last")
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(settings.clipboardHistorySize) },
                        set: { settings.clipboardHistorySize = Int($0) }
                    ), in: 5...50, step: 5).frame(width: 150)
                    Text("\(settings.clipboardHistorySize)").frame(width: 40, alignment: .trailing)
                }
                Divider()
                Button("Clear clipboard history", role: .destructive) { ClipboardStore.shared.clear() }
                    .buttonStyle(.link)
            }
            Text("History is kept in memory only and cleared when Notchless quits.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

// MARK: - Privacy indicator

struct PrivacyPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .privacyDot)
            CardGroup {
                ToggleRow(title: "Show privacy indicator", isOn: $settings.privacyIndicatorEnabled)
            }
            Text("Pulses a green dot when the camera is in use and an orange dot for the microphone, like macOS's own indicator.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}
