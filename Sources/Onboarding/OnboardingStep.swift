import SwiftUI

enum PermissionKind {
    case calendar, location, bluetooth, accessibility, camera, microphone
}

/// An app shown as an example icon on a priming card.
enum AppRef {
    case bundle(String)   // real installed-app icon, resolved via NSWorkspace
    case symbol(String)   // SF Symbol fallback

    var label: String {
        switch self {
        case .bundle(let id): return AppRef.name(for: id)
        case .symbol: return ""
        }
    }

    private static func name(for id: String) -> String {
        switch id {
        case "com.apple.iCal": return "Calendar"
        case "com.flexibits.fantastical2.mac": return "Fantastical"
        case "notion.id": return "Notion"
        case "com.apple.weather": return "Weather"
        case "com.apple.Maps": return "Maps"
        case "com.apple.Safari": return "Safari"
        case "com.google.Chrome": return "Chrome"
        case "com.apple.systempreferences": return "Settings"
        default: return ""
        }
    }
}

/// One page in the onboarding walkthrough.
struct OnboardingStep: Identifiable {
    let id = UUID()
    var title: String
    var badgeSymbol: String
    var badgeColor: Color
    var apps: [AppRef]
    var appLabels: [String]
    var subtitle: String?
    var permission: PermissionKind?
    /// Highlight the "Allow" button in the illustration (permission steps).
    var highlightAllow: Bool

    static let all: [OnboardingStep] = [
        OnboardingStep(
            title: "Welcome to Notchless",
            badgeSymbol: "sparkles", badgeColor: .teal,
            apps: [], appLabels: [],
            subtitle: "A Dynamic Island for your Mac. Let's turn on a few features — you can change any of this later in Settings.",
            permission: nil, highlightAllow: false
        ),
        OnboardingStep(
            title: "Notchless needs your permission to display your upcoming calendar events.",
            badgeSymbol: "calendar", badgeColor: .red,
            apps: [.bundle("com.apple.iCal"), .bundle("com.flexibits.fantastical2.mac"), .bundle("notion.id")],
            appLabels: ["Calendar", "Fantastical", "Notion"],
            subtitle: "Choose \"Allow\" once macOS requests permission to interact on behalf of Notchless.",
            permission: .calendar, highlightAllow: true
        ),
        OnboardingStep(
            title: "Notchless needs your permission to show local weather beside your calendar.",
            badgeSymbol: "location.fill", badgeColor: .blue,
            apps: [.bundle("com.apple.weather"), .bundle("com.apple.Maps"), .symbol("cloud.sun.fill")],
            appLabels: ["Weather", "Maps", "Weather"],
            subtitle: "Choose \"Allow\" once macOS requests your location.",
            permission: .location, highlightAllow: true
        ),
        OnboardingStep(
            title: "Notchless needs your permission to show your connected audio devices.",
            badgeSymbol: "dot.radiowaves.left.and.right", badgeColor: .blue,
            apps: [.symbol("airpods"), .symbol("airpodspro"), .symbol("airpodsmax")],
            appLabels: ["AirPods", "AirPods Pro", "AirPods Max"],
            subtitle: "Choose \"Allow\" once macOS requests Bluetooth access.",
            permission: .bluetooth, highlightAllow: true
        ),
        OnboardingStep(
            title: "Notchless needs Accessibility access to use the media keys for the brightness HUD.",
            badgeSymbol: "slider.horizontal.3", badgeColor: .purple,
            apps: [.symbol("sun.max.fill"), .symbol("speaker.wave.2.fill"), .symbol("keyboard")],
            appLabels: ["Display", "Sound", "Keys"],
            subtitle: "We'll open System Settings → Privacy & Security → Accessibility. Turn on Notchless.",
            permission: .accessibility, highlightAllow: true
        ),
        OnboardingStep(
            title: "Notchless can show a camera mirror in the notch.",
            badgeSymbol: "camera.fill", badgeColor: .pink,
            apps: [.symbol("person.crop.circle"), .symbol("video.fill"), .symbol("sparkles")],
            appLabels: ["Mirror", "Calls", "Look sharp"],
            subtitle: "Choose \"Allow\" once macOS requests camera access. You can open it any time from the menu.",
            permission: .camera, highlightAllow: true
        ),
        OnboardingStep(
            title: "Notchless can type for you — just speak.",
            badgeSymbol: "mic.fill", badgeColor: .teal,
            apps: [.symbol("waveform"), .symbol("keyboard"), .symbol("text.cursor")],
            appLabels: ["Speak", "It types", "Anywhere"],
            subtitle: "Choose \"Allow\" once macOS requests Microphone and Speech Recognition. Hold Control + Option and talk — dictation runs on-device.",
            permission: .microphone, highlightAllow: true
        ),
        OnboardingStep(
            title: "You're all set.",
            badgeSymbol: "checkmark", badgeColor: .green,
            apps: [], appLabels: [],
            subtitle: "Notchless lives in your menu bar. Right-click the notch any time for Settings.",
            permission: nil, highlightAllow: false
        ),
    ]
}
