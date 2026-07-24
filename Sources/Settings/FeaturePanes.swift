import SwiftUI

// MARK: - Battery

struct BatteryPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .battery)
            SectionLabel("Notch")
            CardGroup {
                ToggleRow(title: "Show battery activity", isOn: $settings.batteryEnabled)
                CardDivider()
                ToggleRow(title: "Show percentage", isOn: $settings.batteryShowPercentage)
            }
            SectionLabel("Alerts")
            CardGroup {
                SliderRow(
                    title: "Low battery at",
                    value: Binding(
                        get: { Double(settings.batteryLowThreshold) },
                        set: { settings.batteryLowThreshold = Int($0) }
                    ),
                    range: 5...50,
                    step: 5,
                    valueText: { "\(Int($0))%" }
                )
                CardDivider()
                ToggleRow(title: "Notify when fully charged", isOn: $settings.batteryNotifyCharged)
            }
        }
    }
}

// MARK: - Connectivity / Focus / Display / Sound (notification toggles)

struct ConnectivityPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .connectivity)
            CardGroup {
                ToggleRow(title: "Connectivity notifications", isOn: $settings.connectivityEnabled)
            }
            Footnote("Shows a notch banner when AirPods or other audio devices connect or disconnect.")
        }
    }
}

struct FocusPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .focus)
            CardGroup {
                ToggleRow(title: "Focus notifications", isOn: $settings.focusEnabled)
            }
            Footnote("Announces Focus mode changes (Do Not Disturb, Work, Sleep…) in the notch.")
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
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .display)
            CardGroup {
                ToggleRow(title: "Brightness HUD", isOn: $settings.displayHUDEnabled)
            }
            Footnote("Replaces the system brightness overlay with one anchored to the notch. Built-in display only.")

            SectionLabel("Behavior")
            CardGroup {
                MenuRow(title: "Position", options: HUDPosition.allCases, selection: $settings.hudPosition) { $0.displayName }
            }
            .disabled(!settings.displayHUDEnabled)

            SectionLabel("External Displays")
            CardGroup {
                ToggleRow(title: "Control external displays via BetterDisplay/Lunar",
                          isOn: $settings.externalBrightnessDelegate)
            }
            .disabled(detectedExternalTool == nil)
            Footnote(externalToolCaption)
        }
    }
}

struct SoundPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .sound)
            CardGroup {
                ToggleRow(title: "Volume HUD", isOn: $settings.soundHUDEnabled)
            }
            Footnote("Replaces the system volume overlay with one anchored to the notch.")

            SectionLabel("Appearance")
            CardGroup {
                ToggleRow(title: "Show mute as empty", isOn: $settings.hudShowMuteAsEmpty)
                CardDivider()
                ToggleRow(title: "Show percentage label", isOn: $settings.hudShowPercentageLabel)
                CardDivider()
                ToggleRow(title: "Show output device", isOn: $settings.hudShowOutputDevice)
            }
            .disabled(!settings.soundHUDEnabled)

            SectionLabel("Behavior")
            CardGroup {
                SliderRow(title: "Hide HUD after", value: $settings.hudHideDelay, range: 0.5...5, step: 0.1,
                          valueText: { String(format: "%.1fs", $0) })
                CardDivider()
                ToggleRow(title: "Show on external volume change", isOn: $settings.showOnExternalVolumeEvent)
                CardDivider()
                MenuRow(title: "Position", options: HUDPosition.allCases, selection: $settings.hudPosition) { $0.displayName }
                CardDivider()
                ToggleRow(title: "Show on all displays", isOn: $settings.hudAllDisplays)
                CardDivider()
                ToggleRow(title: "Play a sound on volume change", isOn: $settings.hudSoundOnChange)
                if settings.hudSoundOnChange {
                    CardDivider()
                    HStack(spacing: 10) {
                        MenuRow(title: "Sound", options: HUDSound.allCases, selection: $settings.hudSoundName) { $0.displayName }
                        FlatButton(title: "Preview") { HUDSoundPlayer.shared.play(settings.hudSoundName) }
                    }
                }
            }
            .disabled(!settings.soundHUDEnabled)
            Footnote("'Top' uses the notch; other positions float on the main display.")

            SectionLabel("System OSD")
            CardGroup {
                ToggleRow(title: "Replace the system volume HUD", isOn: $settings.suppressSystemOSD)
                Footnote(osdCaption)
            }
            .disabled(!settings.soundHUDEnabled)

            // Live HUD style preview — kept for the working style/indicator/accent
            // settings, which the flat-dark spec's Sound content list doesn't call
            // out but which remain functioning settings.
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
                        .strokeBorder(SettingsTheme.cardDivider)
                )
            }
            .disabled(!settings.soundHUDEnabled)

            CardGroup {
                MenuRow(title: "Style", options: HUDStyle.allCases, selection: $settings.hudStyle) { $0.displayName }
                if settings.hudStyle == .circular {
                    CardDivider()
                    MenuRow(title: "Indicator", options: HUDIndicator.allCases, selection: $settings.hudIndicator) { $0.displayName }
                }
                CardDivider()
                ToggleRow(title: "Use accent color", isOn: $settings.hudUseAccentColor)
            }
            .disabled(!settings.soundHUDEnabled)
        }
    }

    @ViewBuilder
    private var hudPreview: some View {
        let sample = HUDKind.sound(level: 0.6, muted: false)
        let options = HUDOptions(from: settings)
        let accent: Color? = settings.hudUseAccentColor ? Color.accentColor : nil
        switch settings.hudStyle {
        case .notch:
            Text("Appears at the notch").font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)
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
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .nowPlaying)
            SectionLabel("Visualizer")
            CardGroup {
                ToggleRow(title: "Album art colour glow", isOn: $settings.albumArtGlow)
                CardDivider()
                ToggleRow(title: "Live audio visualizer", isOn: $settings.liveAudioVisualizer)
                Footnote("Reacts to real system audio (needs the audio-recording permission). Off uses a decorative animation.")
            }
            SectionLabel("Gestures")
            CardGroup {
                ToggleRow(title: "Swipe to seek", isOn: $settings.swipeToSeek)
                Footnote("Two-finger swipe left/right on the notch scrubs the current track ±10s.")
                CardDivider()
                ToggleRow(title: "Show tab bar in expanded view", isOn: $settings.showTabBar)
                Footnote("A row of page icons across the top of the expanded notch; tap or swipe to move between pages.")
            }
            SectionLabel("Source")
            CardGroup {
                MenuRow(title: "Show media from", options: NowPlayingSource.allCases, selection: $settings.nowPlayingSource) { $0.displayName }
                if settings.nowPlayingSource == .specificApps {
                    CardDivider()
                    if settings.nowPlayingSeenApps.isEmpty {
                        Footnote("Play something and the app will appear here to allow.")
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
                CardDivider()
                ToggleRow(title: "Show 15-second skip buttons", isOn: $settings.npShowSkip15)
            }
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
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .calendar)
            CardGroup {
                ToggleRow(title: "Show upcoming events", isOn: $settings.calendarShowEvents)
                CardDivider()
                ToggleRow(title: "Show weather", isOn: $settings.calendarShowWeather)
            }
        }
    }
}

// MARK: - Stats

struct StatsPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .stats)
            CardGroup {
                ToggleRow(title: "Show System Stats in the notch", isOn: $settings.statsEnabled)
                CardDivider()
                ToggleRow(title: "CPU", isOn: $settings.statsShowCPU)
                CardDivider()
                ToggleRow(title: "Memory", isOn: $settings.statsShowMemory)
                CardDivider()
                ToggleRow(title: "Network", isOn: $settings.statsShowNetwork)
                CardDivider()
                SliderRow(title: "Update every", value: $settings.statsRefreshSeconds, range: 1...10, step: 1,
                          valueText: { "\(Int($0))s" })
            }
        }
    }
}

// MARK: - Claude usage

struct ClaudeStatsPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .claudeStats)

            CardGroup {
                ToggleRow(title: "Show Claude usage in the notch", isOn: $settings.claudeUsageEnabled)
            }

            SectionLabel("Compact Notch")
            CardGroup {
                MenuRow(title: "Show", options: ClaudeCompactStyle.allCases, selection: $settings.claudeCompactStyle) { $0.title }
            }

            SectionLabel("Expanded View")
            CardGroup {
                ToggleRow(title: "Session (5-hour)", isOn: $settings.claudeShowSession)
                CardDivider()
                ToggleRow(title: "This week", isOn: $settings.claudeShowWeek)
                CardDivider()
                ToggleRow(title: "Daily spend", isOn: $settings.claudeShowSpend)
                CardDivider()
                ToggleRow(title: "Usage chart", isOn: $settings.claudeShowChart)
                CardDivider()
                ToggleRow(title: "Token breakdown", isOn: $settings.claudeShowLegend)
            }

            if settings.claudeShowChart {
                SectionLabel("Chart")
                CardGroup {
                    MenuRow(title: "Window", options: [7, 14, 30], selection: $settings.claudeChartDays) { "\($0) days" }
                    CardDivider()
                    MenuRow(title: "Plot", options: [false, true], selection: $settings.claudeChartCost) { $0 ? "Cost" : "Tokens" }
                }
            }

            Footnote("Estimated from local Claude Code transcripts (tokens × model pricing); refreshes every 10 minutes.")
        }
    }
}

// MARK: - Timer

struct TimerPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .timer)
            CardGroup {
                ToggleRow(title: "Chime when finished", isOn: $settings.timerSoundOnFinish)
            }
            Footnote("Start a timer from the notch: set the idle activity to Timer, or expand the notch to pick a preset.")
        }
    }
}

// MARK: - Clipboard

struct ClipboardPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .clipboard)
            CardGroup {
                ToggleRow(title: "Remember clipboard history", isOn: $settings.clipboardEnabled)
                CardDivider()
                SliderRow(
                    title: "Keep last",
                    value: Binding(
                        get: { Double(settings.clipboardHistorySize) },
                        set: { settings.clipboardHistorySize = Int($0) }
                    ),
                    range: 5...50,
                    step: 5,
                    valueText: { "\(Int($0))" }
                )
                CardDivider()
                HStack {
                    Spacer()
                    FlatButton(title: "Clear clipboard history", style: .destructive) { ClipboardStore.shared.clear() }
                }
            }
            Footnote("History is kept in memory only and cleared when Notchless quits.")
        }
    }
}

// MARK: - Privacy indicator

struct PrivacyPane: View {
    @ObservedObject var settings: SettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .privacyDot)
            CardGroup {
                ToggleRow(title: "Show privacy indicator", isOn: $settings.privacyIndicatorEnabled)
            }
            Footnote("Pulses a green dot when the camera is in use and an orange dot for the microphone, like macOS's own indicator.")
        }
    }
}
