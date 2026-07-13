import Foundation

/// Per-HUD display options (mute-as-empty bar, percentage label, output-device
/// glyph). Read from `SettingsStore` and threaded into `HUDView`/`NotchSizing`
/// so the drawn panel and its sizing always agree.
struct HUDOptions: Equatable {
    var showMuteAsEmpty: Bool
    var showPercentageLabel: Bool
    var showOutputDevice: Bool

    static let `default` = HUDOptions(showMuteAsEmpty: true, showPercentageLabel: false, showOutputDevice: true)

    init(showMuteAsEmpty: Bool, showPercentageLabel: Bool, showOutputDevice: Bool) {
        self.showMuteAsEmpty = showMuteAsEmpty
        self.showPercentageLabel = showPercentageLabel
        self.showOutputDevice = showOutputDevice
    }

    @MainActor
    init(from s: SettingsStore) {
        self.showMuteAsEmpty = s.hudShowMuteAsEmpty
        self.showPercentageLabel = s.hudShowPercentageLabel
        self.showOutputDevice = s.hudShowOutputDevice
    }
}
