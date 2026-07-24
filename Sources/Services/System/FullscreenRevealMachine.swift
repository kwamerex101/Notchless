import CoreGraphics
import Foundation

/// Decides whether the notch panel is visible and interactive while a
/// fullscreen app owns the notch's screen.
///
/// A pure value type: no AppKit, no timers of its own. The caller drives it
/// with `update(_:now:)` on every relevant signal (mouse move, content
/// change, fullscreen change) and, when `Output.graceDeadline` is non-nil,
/// re-invokes `update` at that deadline so the grace period can expire.
struct FullscreenRevealMachine {
    enum State: Equatable {
        case idle
        case hidden
        case revealed
    }

    struct Input {
        /// `SettingsStore.hideInFullscreen`.
        var hidingEnabled: Bool
        /// `NotchViewModel.fullscreenActive`.
        var fullscreenActive: Bool
        /// `NSEvent.mouseLocation`, bottom-left origin.
        var cursor: CGPoint
        /// The notch screen's frame, bottom-left origin.
        var screenFrame: CGRect
        /// The notch's interactive rect, in screen space.
        var notchRect: CGRect
        var content: NotchContent
        var interaction: Interaction
    }

    struct Output: Equatable {
        var alpha: CGFloat
        var allowsInteraction: Bool
        /// When non-nil the caller must re-invoke `update` at this time so the
        /// grace period can expire. Nil when no timer is pending.
        var graceDeadline: Date?
    }

    static let bandHeight: CGFloat = 4
    static let grace: TimeInterval = 0.4
    /// Exposed for the caller's fade-in/out animation; not used in this
    /// type's own logic.
    static let fadeDuration: TimeInterval = 0.18

    private(set) var state: State = .idle

    /// Pending grace-period deadline, tracked internally so repeated
    /// `update` calls while disengaged don't restart the timer.
    private var graceDeadline: Date?

    mutating func update(_ input: Input, now: Date) -> Output {
        guard input.hidingEnabled, input.fullscreenActive else {
            state = .idle
            graceDeadline = nil
            return Output(alpha: 1, allowsInteraction: true, graceDeadline: nil)
        }

        // holdsOpen is true for any content that is actively presenting
        // something the user needs to see — without this such content would
        // render at alpha 0 in fullscreen, unreachable behind the grace
        // period. That covers: a HUD or transient notification (`.hud`,
        // `.notification`), an expanded tab (`.expanded`), an in-progress
        // dictation session (`.dictation`, any phase — recording, or
        // transcribing/cleaning/success/error while the user is still
        // reading the result), the camera mirror (`.mirror`), and an open
        // file tray (`.fileTray(expanded: true)`).
        //
        // Deliberately excluded: `.idle` (ambient, nothing to see), `.bare`
        // (no content at all), and `.fileTray(expanded: false)` (the
        // collapsed resting tray — not actively presenting anything, so it
        // must not force the panel visible).
        let holdsOpen: Bool
        switch input.content {
        case .hud, .notification, .expanded, .dictation, .mirror, .fileTray(expanded: true):
            holdsOpen = true
        default:
            holdsOpen = input.interaction == .expanded
        }

        let band = CGRect(
            x: input.screenFrame.minX,
            y: input.screenFrame.maxY - Self.bandHeight,
            width: input.screenFrame.width,
            height: Self.bandHeight
        )
        let cursorEngaged = input.notchRect.contains(input.cursor) || band.contains(input.cursor)

        if holdsOpen || cursorEngaged {
            state = .revealed
            graceDeadline = nil
            return Output(alpha: 1, allowsInteraction: true, graceDeadline: nil)
        }

        // Nothing engages the machine any more. This single branch covers
        // both spec bullets — "cursor leaves the notch rect" and "cursor
        // enters the band then leaves without reaching the notch rect" —
        // because both reduce to the same condition once expressed as
        // `!holdsOpen && !cursorEngaged`.
        if state == .revealed {
            let deadline = graceDeadline ?? now.addingTimeInterval(Self.grace)
            graceDeadline = deadline
            if now < deadline {
                return Output(alpha: 1, allowsInteraction: true, graceDeadline: deadline)
            }
            state = .hidden
            graceDeadline = nil
            return Output(alpha: 0, allowsInteraction: false, graceDeadline: nil)
        }

        // Entering fullscreen (from .idle) with nothing engaging goes
        // straight to .hidden — grace only applies when leaving .revealed.
        state = .hidden
        graceDeadline = nil
        return Output(alpha: 0, allowsInteraction: false, graceDeadline: nil)
    }
}
