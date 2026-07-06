import SwiftUI

struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(section: .general)

            // Core toggles
            CardGroup {
                ToggleRow(title: "Launch at login", isOn: $settings.launchAtLogin)
                Divider()
                ToggleRow(title: "Sync settings via iCloud", isOn: $settings.syncViaICloud)
                Divider()
                ToggleRow(title: "Hide in fullscreen", isOn: $settings.hideInFullscreen)
                Divider()
                ToggleRow(title: "Hide in mission control", isOn: $settings.hideInMissionControl)
                Divider()
                ToggleRow(title: "Hide from screen capture", isOn: $settings.hideFromScreenCapture)
                Divider()
                ToggleRow(title: "Force simulated notch", isOn: $settings.forceSimulatedNotch)
                SegmentedCards(
                    options: SimulatedDisplay.allCases,
                    selection: $settings.simulatedDisplay,
                    title: { $0.title },
                    systemImage: { $0.systemImage }
                )
                .padding(.top, 4)
            }

            // Idle activity
            SectionLabel("Idle Activity")
            CardGroup {
                ToggleRow(title: "Most Recent", isOn: $settings.idleMostRecent, systemImage: "clock")
                SegmentedCards(
                    options: NotchActivity.allCases.filter { $0 != .privacy },
                    selection: $settings.idleActivity,
                    title: { $0.pickerTitle },
                    systemImage: { $0.pickerImage }
                )
                .padding(.top, 4)
                if settings.idleActivity == .duo {
                    Divider()
                    ToggleRow(title: "Force enable activity", isOn: $settings.forceEnableActivity)
                }
            }

            // Appearance
            SectionLabel("Liquid Glass")
            CardGroup {
                SegmentedCards(
                    options: GlassStyle.allCases,
                    selection: $settings.glassStyle,
                    title: { $0.title },
                    systemImage: { $0 == .clear ? "circle.dotted" : "circle.fill" }
                )
                Divider()
                HStack {
                    Text("Intensity")
                    Spacer()
                    Slider(value: $settings.glassIntensity, in: 0...1).frame(width: 160)
                    Text("\(Int(settings.glassIntensity * 100))%").frame(width: 42, alignment: .trailing)
                }
                Text("Choose a Clear or Tinted glass look for the notch and Settings, and how strong it is.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Behaviour
            SectionLabel("Behaviour")
            CardGroup {
                ToggleRow(title: "Progressive blur", isOn: $settings.progressiveBlur)
                Divider()
                ToggleRow(title: "Haptic feedback", isOn: $settings.hapticFeedback)
            }
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
        case .privacy: return "Privacy"
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
        case .privacy: return "checkmark.shield"
        }
    }
}

// MARK: - Shared building blocks

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }
}

struct CardGroup<Content: View>: View {
    @ViewBuilder var content: Content
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    var body: some View {
        VStack(spacing: 10) { content }
            .padding(14)
            .liquidGlass(in: shape, fallback: .regularMaterial)
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var systemImage: String? = nil

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 18)
            }
            Text(title)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(.green)
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

/// The segmented card picker used for display target and idle activity.
struct SegmentedCards<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    let systemImage: (Option) -> String

    var body: some View {
        // A wrapping grid so many options (e.g. the idle activities) flow into
        // even rows instead of cramming into one line.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                VStack(spacing: 6) {
                    Image(systemName: systemImage(option))
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text(title(option))
                        .font(.caption)
                        .foregroundStyle(selected ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(selected ? 0.08 : 0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
                        )
                )
                .contentShape(Rectangle())
                .onTapGesture { selection = option }
            }
        }
    }
}
