import SwiftUI

/// Target geometry for a given content state, derived from the physical notch
/// metrics. Tunable against `references/` — see PLAN.md §3.
struct NotchSizing: Equatable {
    var width: CGFloat
    var height: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    static func size(for content: NotchContent, metrics: NotchMetrics) -> NotchSizing {
        let w = metrics.notchWidth
        let h = metrics.notchHeight

        switch content {
        case .bare:
            return NotchSizing(width: w, height: h, topRadius: 7, bottomRadius: 9)

        case let .idle(activity):
            switch activity {
            case .none, .playing, .auto:
                return NotchSizing(width: w + 128, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .calendar:
                return NotchSizing(width: w + 96, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .duo:
                return NotchSizing(width: w + 150, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .dictation:
                return NotchSizing(width: w + 128, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .battery:
                // +150 (not +110): each wing must clear the `edgeInset` plus a
                // full "100%" readout, else the leading "1" falls into the
                // physical notch cutout and reads as "00%".
                return NotchSizing(width: w + 150, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .stats:
                // Same reasoning as .battery — CPU can read "100%".
                return NotchSizing(width: w + 150, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .timer:
                return NotchSizing(width: w + 110, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .clipboard:
                return NotchSizing(width: w + 96, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .todos:
                return NotchSizing(width: w + 128, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .privacy:
                return NotchSizing(width: w + 130, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .claudeUsage:
                return NotchSizing(width: w + 120, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .goals:
                // Each wing must clear the notch: the leading ring + percent (up
                // to "100%") needs ~64pt past the edge inset, so the notch's left
                // edge — at (width − w)/2 — has to sit beyond that. +190 keeps a
                // 3-digit percent fully visible; w + 150 clipped it into the notch.
                return NotchSizing(width: w + 190, height: h + 2, topRadius: 8, bottomRadius: 11)
            }

        case .hud:
            return NotchSizing(width: w + 250, height: h + 28, topRadius: 9, bottomRadius: 18)

        case .notification:
            return NotchSizing(width: w + 300, height: h + 30, topRadius: 9, bottomRadius: 20)

        case .mirror:
            return NotchSizing(width: max(w + 40, 360), height: 250, topRadius: 10, bottomRadius: 24)

        case .dictation:
            return NotchSizing(width: max(w + 40, 400), height: h + 66, topRadius: 10, bottomRadius: 22)

        case let .fileTray(isExpanded):
            if isExpanded {
                return NotchSizing(width: max(w + 40, 420), height: 130, topRadius: 10, bottomRadius: 24)
            } else {
                return NotchSizing(width: w + 96, height: h + 2, topRadius: 8, bottomRadius: 11)
            }

        case let .expanded(activity):
            switch activity {
            case .playing, .none, .auto:
                return NotchSizing(width: max(w + 40, 480), height: 178, topRadius: 10, bottomRadius: 24)
            case .calendar:
                return NotchSizing(width: max(w + 40, 470), height: 196, topRadius: 10, bottomRadius: 24)
            case .duo:
                return NotchSizing(width: max(w + 40, 560), height: 158, topRadius: 10, bottomRadius: 24)
            case .dictation:
                return NotchSizing(width: max(w + 40, 400), height: h + 66, topRadius: 10, bottomRadius: 22)
            case .battery:
                return NotchSizing(width: max(w + 40, 360), height: 128, topRadius: 10, bottomRadius: 24)
            case .stats:
                return NotchSizing(width: max(w + 40, 420), height: 140, topRadius: 10, bottomRadius: 24)
            case .timer:
                return NotchSizing(width: max(w + 40, 380), height: 128, topRadius: 10, bottomRadius: 24)
            case .clipboard:
                return NotchSizing(width: max(w + 40, 420), height: 200, topRadius: 10, bottomRadius: 24)
            case .todos:
                return NotchSizing(width: max(w + 40, 420), height: 220, topRadius: 10, bottomRadius: 24)
            case .privacy:
                return NotchSizing(width: max(w + 40, 360), height: 120, topRadius: 10, bottomRadius: 24)
            case .claudeUsage:
                return NotchSizing(width: max(w + 40, 470), height: 196, topRadius: 10, bottomRadius: 24)
            case .goals:
                // Placeholder sizing until Task 7 ships the real expanded view.
                return NotchSizing(width: max(w + 40, 420), height: 200, topRadius: 10, bottomRadius: 24)
            }
        }
    }
}
