import Foundation
import CoreGraphics

/// A hotkey binding: a modifier combo mapped to a target. `id == nil` is the main
/// dictation hotkey; a non-nil id is a mode's dedicated key.
struct HotkeyBinding: Equatable {
    let id: UUID?
    let flags: CGEventFlags
}

/// Pure matching of held modifier flags to a binding.
enum HotkeyMatcher {
    /// The modifier bits our combos use; everything else (caps lock, numpad, shift) is ignored.
    static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]

    /// The first binding whose combo EXACTLY equals the held modifiers (masked), or nil.
    /// Order bindings main-first so the main hotkey wins any duplicate combo.
    static func match(held: CGEventFlags, bindings: [HotkeyBinding]) -> HotkeyBinding? {
        let masked = held.intersection(modifierMask)
        guard !masked.isEmpty else { return nil }
        return bindings.first { $0.flags.intersection(modifierMask) == masked }
    }
}
