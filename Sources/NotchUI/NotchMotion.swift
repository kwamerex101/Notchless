import SwiftUI

/// The app's complete motion vocabulary. Every notch animation should use one
/// of these so the feel stays coherent — springs for shape/interaction,
/// one shared curve for level fills, and named dwell/dismiss intervals.
enum NotchMotion {
    /// Shape + size morphs (expand/collapse, page changes).
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Transients arriving/leaving (HUD, notification, dictation).
    static let quick = Animation.spring(response: 0.3, dampingFraction: 0.82)
    /// Micro-interactions: hover, press, checkbox pops.
    static let micro = Animation.spring(response: 0.18, dampingFraction: 0.7)
    /// The single curve for every ring/bar/level fill (battery, goals, stats, HUD).
    static let fill = Animation.spring(response: 0.35, dampingFraction: 0.8)
    /// Audio spectrum smoothing.
    static let spectrum = Animation.spring(response: 0.16, dampingFraction: 0.6)

    // Timing intervals (seconds).
    static let hoverDwell: TimeInterval = 0.15
    static let collapseGrace: TimeInterval = 0.35
    static let hudDismiss: TimeInterval = 1.4
    static let dictationDismiss: TimeInterval = 2.2

    /// Returns `base`, or a short opacity-friendly ease when Reduce Motion is on
    /// (springs read as motion; a brief ease reads as a state change).
    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : base
    }
}
