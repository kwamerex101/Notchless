import SwiftUI

/// Target geometry for a given content state, derived from the physical notch
/// metrics. Tunable against `references/` — see PLAN.md §3.
struct NotchSizing: Equatable {
    var width: CGFloat
    var height: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// The interactive band for `content` in screen space (bottom-left origin,
    /// matching `NSEvent.mouseLocation`), padded by `pad` for easy targeting.
    /// Single source of truth for the hover region.
    static func screenBand(for content: NotchContent, metrics: NotchMetrics, pad: CGFloat, dictationSettled: Bool = true) -> CGRect {
        let sizing = size(for: content, metrics: metrics, dictationSettled: dictationSettled)
        return CGRect(
            x: metrics.notchCenterX - sizing.width / 2 - pad,
            y: metrics.screenTopY - sizing.height - pad,
            width: sizing.width + pad * 2,
            height: sizing.height + pad * 2
        )
    }

    /// Width for the HUD panel, growing to fit the option-driven extras
    /// (percentage label, output-device glyph). PURE — unit-tested in
    /// `HUDSizingTests`. Called from `size(for:)` so the drawn `NotchShape`,
    /// `NotchHostingView.hitTest`, and `NotchMouseTracker`'s click-through band
    /// all agree.
    static func hudWidth(base: CGFloat, kind: HUDKind, options: HUDOptions) -> CGFloat {
        var width = base
        if options.showPercentageLabel {
            width += 44
        }
        if case .sound = kind, options.showOutputDevice {
            width += 26
        }
        return width
    }

    static func size(for content: NotchContent, metrics: NotchMetrics, dictationSettled: Bool = true) -> NotchSizing {
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
                return NotchSizing(width: w + 138, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .clipboard:
                return NotchSizing(width: w + 96, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .todos:
                return NotchSizing(width: w + 128, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .privacy:
                return NotchSizing(width: w + 130, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .claudeUsage:
                return NotchSizing(width: w + 154, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .goals:
                // Each wing must clear the notch: the leading ring + percent (up
                // to "100%") needs ~64pt past the edge inset, so the notch's left
                // edge — at (width − w)/2 — has to sit beyond that. +190 keeps a
                // 3-digit percent fully visible; w + 150 clipped it into the notch.
                return NotchSizing(width: w + 190, height: h + 2, topRadius: 8, bottomRadius: 11)
            case .meeting:
                // +160 (not +128): the recording elapsed can read up to
                // `h:mm:ss` (7 chars), so each wing needs the same clearance
                // the 4-char "100%" battery readout does (+150) plus a hair,
                // else the leading digits fall into the physical notch cutout.
                return NotchSizing(width: w + 160, height: h + 2, topRadius: 8, bottomRadius: 11)
            }

        case let .hud(kind):
            // All production call sites (`NotchRootView`, `NotchHostingView.hitTest`,
            // `NotchMouseTracker`) already run on the main actor; `size(for:)` stays
            // nonisolated so pure sizing tests (e.g. `DictationSizingTests`) can keep
            // calling it directly without hopping actors.
            let options = MainActor.assumeIsolated { HUDOptions(from: SettingsStore.shared) }
            let width = hudWidth(base: w + 250, kind: kind, options: options)
            return NotchSizing(width: width, height: h + 36, topRadius: 9, bottomRadius: 18)

        case .notification:
            return NotchSizing(width: w + 300, height: h + 38, topRadius: 9, bottomRadius: 20)

        case .mirror:
            return NotchSizing(width: max(w + 40, 360), height: 250, topRadius: 10, bottomRadius: 24)

        case let .dictation(phase):
            switch phase {
            case .recording:
                if dictationSettled {
                    // Full panel: waveform + transcript + control row.
                    return NotchSizing(width: max(w + 40, 420), height: h + 96, topRadius: 10, bottomRadius: 22)
                } else {
                    // Entry sliver: waveform only.
                    return NotchSizing(width: max(w + 40, 260), height: h + 22, topRadius: 9, bottomRadius: 16)
                }
            case .transcribing, .cleaning:
                // Slightly shorter: shimmer + transcript + label, no control row.
                return NotchSizing(width: max(w + 40, 400), height: h + 74, topRadius: 10, bottomRadius: 22)
            case .success, .error:
                // Compact result chip.
                return NotchSizing(width: max(w + 40, 320), height: h + 40, topRadius: 10, bottomRadius: 20)
            }

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
                return NotchSizing(width: max(w + 40, 540), height: 158, topRadius: 10, bottomRadius: 24)
            case .dictation:
                return NotchSizing(width: max(w + 40, 480), height: h + 74, topRadius: 10, bottomRadius: 24)
            case .battery:
                return NotchSizing(width: max(w + 40, 360), height: 110, topRadius: 10, bottomRadius: 24)
            case .stats:
                return NotchSizing(width: max(w + 40, 420), height: 140, topRadius: 10, bottomRadius: 24)
            case .timer:
                return NotchSizing(width: max(w + 40, 380), height: 128, topRadius: 10, bottomRadius: 24)
            case .clipboard:
                return NotchSizing(width: max(w + 40, 420), height: 200, topRadius: 10, bottomRadius: 24)
            case .todos:
                return NotchSizing(width: max(w + 40, 420), height: 210, topRadius: 10, bottomRadius: 24)
            case .privacy:
                return NotchSizing(width: max(w + 40, 360), height: 120, topRadius: 10, bottomRadius: 24)
            case .claudeUsage:
                return NotchSizing(width: max(w + 40, 470), height: 196, topRadius: 10, bottomRadius: 24)
            case .goals:
                // Placeholder sizing until Task 7 ships the real expanded view.
                return NotchSizing(width: max(w + 40, 420), height: 200, topRadius: 10, bottomRadius: 24)
            case .meeting:
                return NotchSizing(width: max(w + 40, 380), height: 128, topRadius: 10, bottomRadius: 24)
            }
        }
    }
}
