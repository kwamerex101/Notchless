import AppKit

/// Force Touch trackpad haptics for notch open/close/scrub. See PLAN.md §1.3.
enum HapticService {
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
