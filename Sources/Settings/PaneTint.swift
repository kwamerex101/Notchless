import SwiftUI

/// The accent tint for the current settings pane. Each pane is themed by its
/// `SettingsSection.tint`; this is set once in `SettingsView` and consumed by
/// the shared components (`SectionLabel`, `SegmentedCards`, `CardGroup`), so
/// panes inherit their tint with no per-call plumbing. Defaults to the system
/// accent for previews / any view rendered outside a pane.
private struct PaneTintKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var paneTint: Color {
        get { self[PaneTintKey.self] }
        set { self[PaneTintKey.self] = newValue }
    }
}
