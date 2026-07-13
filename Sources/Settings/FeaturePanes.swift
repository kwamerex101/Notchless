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

    private var detectedExternalTool: ExternalBrightnessTool? {
        ExternalBrightnessBridge.shared.detectTool()
    }

    private var externalToolCaption: String {
        switch detectedExternalTool {
        case .betterDisplay: return "Detected: BetterDisplay."
        case .lunar: return "Detected: Lunar."
        case nil: return "Install BetterDisplay or Lunar to control external-display brightness."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .display)
            CardGroup {
                ToggleRow(title: "Brightness HUD", isOn: $settings.displayHUDEnabled)
            }
            Text("Replaces the system brightness overlay with one anchored to the notch. Built-in display only.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            SectionLabel("Behavior")
            CardGroup {
                HStack {
                    Text("Position")
                    Spacer()
                    SettingsPicker(options: HUDPosition.allCases, selection: $settings.hudPosition) { $0.displayName }
                }
            }
            .disabled(!settings.displayHUDEnabled)

            SectionLabel("External Displays")
            CardGroup {
                ToggleRow(title: "Control external displays via BetterDisplay/Lunar",
                          isOn: $settings.externalBrightnessDelegate)
            }
            .disabled(detectedExternalTool == nil)
            Text(externalToolCaption)
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

            SectionLabel("Appearance")
            CardGroup {
                ToggleRow(title: "Show mute as empty", isOn: $settings.hudShowMuteAsEmpty)
                Divider()
                ToggleRow(title: "Show percentage label", isOn: $settings.hudShowPercentageLabel)
                Divider()
                ToggleRow(title: "Show output device", isOn: $settings.hudShowOutputDevice)
            }
            .disabled(!settings.soundHUDEnabled)

            SectionLabel("Behavior")
            CardGroup {
                HStack {
                    Text("Hide HUD after")
                    Spacer()
                    Slider(value: $settings.hudHideDelay, in: 0.5...5, step: 0.1).frame(width: 150)
                    Text(String(format: "%.1fs", settings.hudHideDelay)).frame(width: 44, alignment: .trailing)
                }
                Divider()
                ToggleRow(title: "Show on external volume change", isOn: $settings.showOnExternalVolumeEvent)
                Divider()
                HStack {
                    Text("Position")
                    Spacer()
                    SettingsPicker(options: HUDPosition.allCases, selection: $settings.hudPosition) { $0.displayName }
                }
                Divider()
                ToggleRow(title: "Show on all displays", isOn: $settings.hudAllDisplays)
                Divider()
                ToggleRow(title: "Play a sound on volume change", isOn: $settings.hudSoundOnChange)
                if settings.hudSoundOnChange {
                    Divider()
                    HStack {
                        Text("Sound")
                        Spacer()
                        SettingsPicker(options: HUDSound.allCases, selection: $settings.hudSoundName) { $0.displayName }
                        Button("Preview") { HUDSoundPlayer.shared.play(settings.hudSoundName) }
                    }
                }
            }
            .disabled(!settings.soundHUDEnabled)
            Text("'Top' uses the notch; other positions float on the main display.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            SectionLabel("System OSD")
            CardGroup {
                ToggleRow(title: "Replace the system volume HUD", isOn: $settings.suppressSystemOSD)
                Text(osdCaption)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!settings.soundHUDEnabled)

            SectionLabel("HUD Style")
            CardGroup {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.15)],
                                              startPoint: .top, endPoint: .bottom))
                    hudPreview
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                )
            }
            .disabled(!settings.soundHUDEnabled)

            CardGroup {
                HStack {
                    Text("Style")
                    Spacer()
                    SettingsPicker(options: HUDStyle.allCases, selection: $settings.hudStyle) { $0.displayName }
                }
                if settings.hudStyle == .circular {
                    Divider()
                    HStack {
                        Text("Indicator")
                        Spacer()
                        SettingsPicker(options: HUDIndicator.allCases, selection: $settings.hudIndicator) { $0.displayName }
                    }
                }
                Divider()
                ToggleRow(title: "Use accent color", isOn: $settings.hudUseAccentColor)
            }
            .disabled(!settings.soundHUDEnabled)

            Spacer()
        }
    }

    @ViewBuilder
    private var hudPreview: some View {
        let sample = HUDKind.sound(level: 0.6, muted: false)
        let options = HUDOptions(from: settings)
        let accent: Color? = settings.hudUseAccentColor ? Color.accentColor : nil
        switch settings.hudStyle {
        case .notch:
            Text("Appears at the notch").font(.caption).foregroundStyle(.secondary)
        case .classic:
            ClassicHUDView(kind: sample, options: options, accent: accent)
        case .ios:
            IOSHUDView(kind: sample, options: options, accent: accent)
        case .circular:
            CircularHUDView(kind: sample, options: options, accent: accent, indicator: settings.hudIndicator)
        }
    }

    private var osdCaption: String {
        var text = "Also hides the Caps Lock and keyboard-backlight overlays while enabled."
        if !OSDSuppressor.isValidatedOnCurrentOS {
            text += " Not yet verified on this macOS version."
        }
        return text
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
                ToggleRow(title: "Show tab bar in expanded view", isOn: $settings.showTabBar)
                Text("A row of page icons across the top of the expanded notch; tap or swipe to move between pages.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SectionLabel("Source")
            CardGroup {
                SettingsPicker(options: NowPlayingSource.allCases, selection: $settings.nowPlayingSource) { $0.displayName }
                if settings.nowPlayingSource == .specificApps {
                    Divider()
                    if settings.nowPlayingSeenApps.isEmpty {
                        Text("Play something and the app will appear here to allow.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(settings.nowPlayingSeenApps, id: \.self) { id in
                            ToggleRow(title: displayName(forBundleID: id), isOn: allowedBinding(for: id))
                        }
                    }
                }
            }
            SectionLabel("Transport")
            CardGroup {
                ToggleRow(title: "Show shuffle button", isOn: $settings.npShowShuffle)
                Divider()
                ToggleRow(title: "Show 15-second skip buttons", isOn: $settings.npShowSkip15)
            }
            Spacer()
        }
    }

    /// Cleans a bundle id into a readable app name — the last dotted
    /// component, capitalized (e.g. `com.apple.Music` → "Music") — falling
    /// back to the raw id when that isn't meaningful.
    private func displayName(forBundleID id: String) -> String {
        guard let last = id.split(separator: ".").last, !last.isEmpty else { return id }
        return String(last).prefix(1).uppercased() + String(last).dropFirst()
    }

    private func allowedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.nowPlayingAllowedApps.contains(id) },
            set: { on in
                if on {
                    if !settings.nowPlayingAllowedApps.contains(id) { settings.nowPlayingAllowedApps.append(id) }
                } else {
                    settings.nowPlayingAllowedApps.removeAll { $0 == id }
                }
            }
        )
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
            CardGroup {
                ToggleRow(title: "Show System Stats in the notch", isOn: $settings.statsEnabled)
            }
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

            CardGroup {
                ToggleRow(title: "Show Claude usage in the notch", isOn: $settings.claudeUsageEnabled)
            }

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
