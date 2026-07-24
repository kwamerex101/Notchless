import SwiftUI
import ApplicationServices

struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .general)

            // Core toggles
            CardGroup {
                ToggleRow(title: "Launch at login", isOn: $settings.launchAtLogin)
                CardDivider()
                ToggleRow(title: "Sync settings via iCloud", isOn: $settings.syncViaICloud)
                CardDivider()
                ToggleRow(title: "Hide in fullscreen", isOn: $settings.hideInFullscreen)
                if !settings.hideInFullscreen {
                    CardDivider()
                    ToggleRow(title: "Collapse activities in fullscreen", isOn: $settings.collapseInFullscreen)
                }
                CardDivider()
                ToggleRow(title: "Hide in mission control", isOn: $settings.hideInMissionControl)
                CardDivider()
                ToggleRow(title: "Hide from screen capture", isOn: $settings.hideFromScreenCapture)
                CardDivider()
                ToggleRow(title: "Force simulated notch", isOn: $settings.forceSimulatedNotch)
                SegmentedCards(
                    options: SimulatedDisplay.allCases,
                    selection: $settings.simulatedDisplay,
                    title: { $0.title },
                    systemImage: { $0.systemImage }
                )
            }

            // Idle activity
            SectionLabel("Idle Activity")
            CardGroup {
                ToggleRow(title: "Most Recent", isOn: $settings.idleMostRecent)
                SegmentedCards(
                    options: NotchActivity.allCases.filter { $0 != .privacy && $0 != .meeting },
                    selection: $settings.idleActivity,
                    title: { $0.pickerTitle },
                    systemImage: { $0.pickerImage }
                )
                if settings.idleActivity == .duo {
                    CardDivider()
                    ToggleRow(title: "Force enable activity", isOn: $settings.forceEnableActivity)
                }
            }

            // Theme — the notch surface tint picker
            SectionLabel("Theme")
            CardGroup {
                Text("Notch surface tint")
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsTheme.text)
                TintSwatchRow(selection: $settings.notchTint)
                Footnote("Tints the notch surface across every state.")
            }

            // Behaviour (includes the Liquid Glass style/intensity controls,
            // which the flat-dark spec doesn't call out but which stay put
            // rather than being dropped).
            SectionLabel("Behaviour")
            CardGroup {
                ToggleRow(title: "Progressive blur", isOn: $settings.progressiveBlur)
                CardDivider()
                ToggleRow(title: "Haptic feedback", isOn: $settings.hapticFeedback)
                CardDivider()
                SegmentedCards(
                    options: GlassStyle.allCases,
                    selection: $settings.glassStyle,
                    title: { $0.title },
                    systemImage: { $0 == .clear ? "circle.dotted" : "circle.fill" }
                )
                SliderRow(title: "Intensity", value: $settings.glassIntensity)
                Footnote("Choose a Clear or Tinted glass look for the notch and Settings, and how strong it is.")
            }

            // Trackpad feedback (system-wide haptics + click sounds)
            SectionLabel("Trackpad Feedback")
            TrackpadFeedbackSection(settings: settings)
        }
    }
}

extension NotchActivity {
    var pickerTitle: String {
        switch self {
        case .auto: return "Auto"
        case .none: return "None"
        case .playing: return "Playing"
        case .calendar: return "Calendar"
        case .duo: return "Duo"
        case .dictation: return "Dictation"
        case .battery: return "Battery"
        case .stats: return "Stats"
        case .timer: return "Timer"
        case .clipboard: return "Clipboard"
        case .todos: return "Tasks"
        case .privacy: return "Privacy"
        case .claudeUsage: return "Claude"
        case .goals: return "Goals"
        case .meeting: return "Meeting"
        }
    }
    var pickerImage: String {
        switch self {
        case .auto: return "sparkles"
        case .none: return "nosign"
        case .playing: return "play.fill"
        case .calendar: return "calendar"
        case .duo: return "rectangle.2.swap"
        case .dictation: return "mic.fill"
        case .battery: return "battery.100"
        case .stats: return "cpu"
        case .timer: return "timer"
        case .clipboard: return "doc.on.clipboard"
        case .todos: return "checklist"
        case .privacy: return "checkmark.shield"
        case .claudeUsage: return "chart.pie.fill"
        case .goals: return "target"
        case .meeting: return "record.circle"
        }
    }
}

// MARK: - Trackpad feedback

/// System-wide scroll/click feedback controls. Availability is probed once —
/// haptics need a built-in Force Touch trackpad; sound works on any Mac.
struct TrackpadFeedbackSection: View {
    @ObservedObject var settings: SettingsStore

    @State private var hapticsAvailable = false
    @State private var gesturesAvailable = false
    @State private var accessibilityGranted = false
    // Re-check trust while visible — grants happen out-of-band in System Settings.
    private let trustTick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        CardGroup {
            ToggleRow(title: "Trackpad feedback", isOn: $settings.trackpadFeedbackEnabled)
            Footnote("Feel and hear a subtle click as you scroll and click anywhere — spaced naturally with your scroll speed.")

            if settings.trackpadFeedbackEnabled {
                if !accessibilityGranted {
                    CardDivider()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SettingsTheme.textSecondary)
                        Text("Needs Accessibility to detect scrolling")
                            .font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
                        Spacer()
                        FlatButton(title: "Grant…") { promptForAccessibility() }
                    }
                }

                CardDivider()
                ToggleRow(title: "Haptics", isOn: $settings.trackpadHapticsEnabled, systemImage: "hand.tap")
                if !hapticsAvailable {
                    Footnote("Haptics need a built-in Force Touch trackpad — sound still works.")
                } else if settings.trackpadHapticsEnabled {
                    SegmentedCards(
                        options: HapticStrength.allCases,
                        selection: $settings.trackpadHapticStrength,
                        title: { $0.title },
                        systemImage: { $0.systemImage }
                    )
                }

                CardDivider()
                ToggleRow(title: "Sound", isOn: $settings.trackpadSoundEnabled, systemImage: "speaker.wave.2")
                if settings.trackpadSoundEnabled {
                    SegmentedCards(
                        options: FeedbackVoice.all,
                        selection: Binding(
                            get: { FeedbackVoice.voice(id: settings.trackpadSoundVoice) },
                            set: { settings.trackpadSoundVoice = $0.id }
                        ),
                        title: { $0.displayName },
                        systemImage: { _ in "waveform" }
                    )
                    SliderRow(title: "Volume", value: $settings.trackpadSoundVolume)
                }

                CardDivider()
                ToggleRow(title: "While scrolling", isOn: $settings.trackpadFeedbackScroll, systemImage: "scroll")
                ToggleRow(title: "While clicking", isOn: $settings.trackpadFeedbackClick, systemImage: "cursorarrow.click")

                CardDivider()
                ToggleRow(title: "Multi-finger gestures", isOn: $settings.trackpadGesturesEnabled, systemImage: "hand.draw")
                if !gesturesAvailable {
                    Footnote("Multi-finger gestures aren't available on this Mac.")
                } else {
                    Footnote("A tick when you swipe between spaces, open Mission Control, or pinch to Launchpad.")
                }

                CardDivider()
                HStack {
                    Footnote("Try the current feel")
                    Spacer()
                    FlatButton(title: "Test") {
                        NotificationCenter.default.post(
                            name: TrackpadFeedbackController.testFeedbackNotification, object: nil)
                    }
                }
            }
        }
        .onAppear {
            hapticsAvailable = TrackpadHapticEngine.probeAvailability()
            gesturesAvailable = MultitouchMonitor.probeAvailability()
            accessibilityGranted = AXIsProcessTrusted()
        }
        .onReceive(trustTick) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    private func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if let url = AppPermission.accessibility.settingsURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSWorkspace.shared.open(url) }
        }
    }
}

// MARK: - Shared building blocks

/// Uppercase section header above a `CardGroup`. See spec §5 "Pane body".
struct SectionLabel: View {
    @Environment(\.paneTint) private var tint
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(SettingsTheme.textTertiary)
    }
}

/// Flat card surface — no material, no border, no shadow. See spec §5 "Card".
///
/// The `VStack`'s `spacing` is 4, not the spec's headline "vertical gap 9" —
/// a `CardDivider` between two rows adds its own 1pt line, and the `VStack`
/// inserts this `spacing` on *both* sides of it (4 + 1 + 4 = 9), so a
/// divided pair of rows ends up the spec's 9pt apart. That 9 is a property
/// of the gap as a whole, including the hairline, not of `spacing` alone —
/// using 9 for `spacing` here double-counted it (9 + 1 + 9 = 19) and bloated
/// the row pitch to ~39pt instead of the spec's ~30. Call sites with no
/// divider between two elements (e.g. a label followed straight by a
/// control row) fall back to this 4pt spacing and should pad up to 9
/// themselves if they need the full card gap.
struct CardGroup<Content: View>: View {
    @Environment(\.paneTint) private var tint
    @ViewBuilder var content: Content
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(shape.fill(SettingsTheme.card))
    }
}

/// A 1pt hairline separating rows inside a `CardGroup`. See `CardGroup` for
/// why the surrounding spacing is 4, not 9.
struct CardDivider: View {
    var body: some View {
        Rectangle().fill(SettingsTheme.cardDivider).frame(height: 1)
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(SettingsTheme.textSecondary).frame(width: 18)
            }
            Text(title).font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
            Spacer()
            FlatSwitch(isOn: $isOn, label: title)
        }
    }
}

struct ToggleCard: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        CardGroup { ToggleRow(title: title, isOn: $isOn) }
    }
}

/// Flat replacement for the native `Toggle` — 34x20, spec §5 "Switch".
/// Keeps the same accessibility contract a `Toggle` would carry.
struct FlatSwitch: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? SettingsTheme.switchOn : SettingsTheme.switchOff)
                Circle()
                    .fill(isOn ? SettingsTheme.switchKnobOn : SettingsTheme.switchKnobOff)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .frame(width: 34, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The chip-grid picker used for display target and idle activity.
/// Spec §5 "Chip grid picker": 5-column grid, text-only chips.
struct SegmentedCards<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let systemImage: (Option) -> String
    @Environment(\.paneTint) private var tint

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Text(title(option))
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? SettingsTheme.onPrimary : SettingsTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9).padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? SettingsTheme.primaryFill : SettingsTheme.card)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
            }
        }
    }
}

/// Label + flat track slider, spec §5 "Slider".
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    /// Snaps dragged values to this increment; `nil` keeps the old continuous
    /// drag. See spec §5 "Slider" — the discrete steps predate the flat-dark
    /// conversion and are restored per call site.
    var step: Double? = nil
    var valueText: (Double) -> String = { "\(Int($0 * 100))%" }

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
            Spacer()
            FlatSlider(value: $value, range: range, step: step).frame(width: 130)
            Text(valueText(value))
                .font(.system(size: 12))
                .foregroundStyle(SettingsTheme.textSecondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

/// The 130x4 track backing `SliderRow`.
private struct FlatSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = span == 0 ? 0 : CGFloat((value - range.lowerBound) / span)
            let fillWidth = max(0, min(width, width * fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(SettingsTheme.switchOff).frame(height: 4)
                Capsule().fill(SettingsTheme.primaryFill).frame(width: fillWidth, height: 4)
                Circle().fill(Color.white).frame(width: 13, height: 13)
                    .offset(x: fillWidth - 6.5)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    guard width > 0 else { return }
                    let f = min(max(0, g.location.x / width), 1)
                    var next = range.lowerBound + Double(f) * span
                    if let step, step > 0 {
                        next = (next / step).rounded() * step
                        next = min(max(next, range.lowerBound), range.upperBound)
                    }
                    value = next
                }
            )
        }
        .frame(height: 20)
    }
}

/// Label + inline picker chip, spec §5 "Menu picker".
struct MenuRow<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) { selection = option }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(label(selection))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.8))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(SettingsTheme.textSecondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.controlChip))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

/// Leading-aligned pill picker, spec §5 "Segmented control".
struct SegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? SettingsTheme.onPrimary : SettingsTheme.textSecondary)
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? SettingsTheme.primaryFill : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SettingsTheme.card))
        .fixedSize()
    }
}

/// The visual weight a `FlatButton` reads as. Spec §5 "Controls".
enum FlatButtonStyle {
    case secondary, primary, destructive
}

/// Flat pill button in secondary / primary / destructive weights.
struct FlatButton: View {
    let title: String
    var style: FlatButtonStyle = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: style == .secondary ? .medium : .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background))
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch style {
        case .secondary: return SettingsTheme.button
        case .primary: return SettingsTheme.primaryFill
        case .destructive: return SettingsTheme.destructiveBg
        }
    }

    private var foreground: Color {
        switch style {
        case .secondary: return SettingsTheme.text
        case .primary: return SettingsTheme.onPrimary
        case .destructive: return SettingsTheme.destructiveText
        }
    }
}

/// 11pt caption text with generous line spacing, spec §5 "Footnote".
struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(SettingsTheme.textTertiary)
            .lineSpacing(5.5) // ~1.5x line height at 11pt
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The notch-tint swatch row for the General pane's THEME section.
/// Spec §5 "New control — Theme".
private struct TintSwatchRow: View {
    @Binding var selection: NotchTint

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NotchTint.allCases) { tint in
                let selected = tint == selection
                Button {
                    selection = tint
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.color)
                            .frame(width: 40, height: 26)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .inset(by: -2)
                                        .stroke(SettingsTheme.windowBody, lineWidth: 2)
                                }
                            }
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .inset(by: -5.5)
                                        .stroke(SettingsTheme.primaryFill, lineWidth: 3.5)
                                }
                            }
                        Text(tint.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(
                                selected
                                    ? Color(red: 235 / 255, green: 238 / 255, blue: 245 / 255).opacity(0.7)
                                    : SettingsTheme.textTertiary
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tint.displayName) tint")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
