import SwiftUI

/// Shared visual constants for the expanded panels, so spacing, chip rounding,
/// and section headers stay consistent instead of drifting per file.
enum NotchDesign {
    /// Standard inner horizontal padding for expanded panels.
    static let panelHPadding: CGFloat = 16
    /// Corner radius for the small inset chips/rows (tasks, goals, files, clips).
    static let chipRadius: CGFloat = 8
    /// Section-header text (the "Tasks" / "Goals" / "Clipboard" titles).
    static let headerFont = Font.system(size: 12, weight: .semibold)
    static let headerOpacity: Double = 0.7
    /// Shared soft-glow radius for tinted chips/indicators.
    static let glowRadius: CGFloat = 5
}

extension View {
    /// Applies the standard expanded-panel section-header styling.
    func notchSectionHeader() -> some View {
        font(NotchDesign.headerFont).foregroundStyle(.white.opacity(NotchDesign.headerOpacity))
    }

    /// Tags album artwork so it morphs between the compact sliver and the
    /// expanded tile. No-op when no namespace is supplied (previews/DebugRender).
    @ViewBuilder func matchedArtwork(_ namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: "artwork", in: namespace)
        } else {
            self
        }
    }
}
