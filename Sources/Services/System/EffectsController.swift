import AppKit
import Combine

/// Applies settings-driven system side-effects: launch-at-login, hide from
/// screen capture, and hide while a fullscreen app is frontmost.
@MainActor
final class EffectsController {
    private let settings: SettingsStore
    private weak var panel: NSPanel?
    private weak var model: NotchViewModel?
    /// Owns panel alpha/interactivity in fullscreen; applyFullscreenState()
    /// hands off to it instead of writing alphaValue itself.
    private weak var reveal: FullscreenRevealController?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsStore, panel: NSPanel?, model: NotchViewModel? = nil, reveal: FullscreenRevealController? = nil) {
        self.settings = settings
        self.panel = panel
        self.model = model
        self.reveal = reveal
    }

    func start() {
        // Launch at login
        settings.$launchAtLogin
            .sink { LoginItem.setEnabled($0) }
            .store(in: &cancellables)

        // Hide from screen capture
        settings.$hideFromScreenCapture
            .sink { [weak self] hidden in
                self?.panel?.sharingType = hidden ? .none : .readOnly
            }
            .store(in: &cancellables)

        // Track whether a fullscreen app is frontmost. Register unconditionally —
        // the handlers gate on the live settings — so toggling the prefs at
        // runtime takes effect without a relaunch. A fullscreen app owns its own
        // Space, so entering/leaving one fires the Space change; activating a
        // different app can land on a fullscreen Space too.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshFullscreenState),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshFullscreenState),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        // When the user turns the pref off while the panel is hidden, bring it
        // back immediately (and re-evaluate when turned on).
        settings.$hideInFullscreen
            .sink { [weak self] on in
                guard let self else { return }
                // Turning off: reset the controller rather than writing alpha
                // behind its back, so its state doesn't desync from actual
                // alpha (it stays desynced until the next fullscreen
                // transition otherwise, mis-driving the next reveal).
                //
                // Turning on: this sink fires from `willSet`, before
                // `settings.hideInFullscreen` commits, so pass `on` through
                // explicitly instead of letting `refreshFullscreenState()`
                // -> `reveal?.evaluate()` re-read the (still-stale) property.
                if on { self.refreshFullscreenStateAndScheduleRecheck(hidingEnabledOverride: on) } else { self.reveal?.reset() }
            }
            .store(in: &cancellables)
        refreshFullscreenState()
    }

    /// Re-evaluates fullscreen for the panel's current screen. Called by
    /// AppDelegate after the panel moves to another display.
    func refresh() { refreshFullscreenState() }

    @objc private func refreshFullscreenState() {
        refreshFullscreenStateAndScheduleRecheck(hidingEnabledOverride: nil)
    }

    private func refreshFullscreenStateAndScheduleRecheck(hidingEnabledOverride: Bool?) {
        applyFullscreenState(hidingEnabledOverride: hidingEnabledOverride)
        // The Space-change notification fires while the fullscreen transition is
        // still animating — window bounds and the menu bar haven't settled — so
        // sample once more after the animation is over. The recheck always
        // re-reads the live (by-then-committed) setting, so it never needs
        // an override.
        settleRecheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyFullscreenState(hidingEnabledOverride: nil) }
        settleRecheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
    private var settleRecheck: DispatchWorkItem?

    private func applyFullscreenState(hidingEnabledOverride: Bool?) {
        let fullscreen = isFullscreenSpaceActive()
        // Only publish real transitions — this fires on every app switch, and a
        // same-value set would still invalidate the whole notch view tree.
        if let model, model.fullscreenActive != fullscreen {
            model.fullscreenActive = fullscreen
        }
        // Hand off to the reveal controller instead of writing alpha
        // directly. No `hideInFullscreen` guard needed here: when hiding is
        // off the machine returns idle/alpha 1 on its own (see
        // FullscreenRevealMachine.update's leading guard), which is the same
        // behavior the old direct write produced.
        reveal?.evaluate(hidingEnabledOverride: hidingEnabledOverride)
    }

    /// Whether window content on the notch's own screen can reach the top edge
    /// AND spans essentially the full screen width (a fullscreen Space, or a
    /// maximized window under a hidden menu bar) — exactly the situations
    /// where the resting notch would cover it.
    private func isFullscreenSpaceActive() -> Bool {
        guard let screen = panel?.screen ?? NSScreen.main,
              let primary = NSScreen.screens.first else { return false }

        // We deliberately do NOT gate on visibleFrame/the menu bar: on external
        // displays NSScreen.visibleFrame keeps a menu-bar reservation even inside a
        // fullscreen Space (Notchless itself lives in the desktop Space), so that
        // heuristic false-negatives there. Instead, look at what's actually on the
        // screen — a normal-level (layer 0) window that reaches the top edge and
        // spans the screen width is a fullscreen Space, or a maximized window under
        // a hidden menu bar: exactly the cases where the resting notch covers real
        // content.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let windows: [(layer: Int, bounds: CGRect)] = list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return (layer, bounds)
        }
        return Self.coversNotchTopBand(
            notchScreenFrame: screen.frame,
            primaryScreenFrame: primary.frame,
            windows: windows
        )
    }

    /// Pure decision behind `isFullscreenSpaceActive`: given the notch screen's
    /// frame, the primary screen's frame (for the AppKit bottom-left → CGWindow
    /// top-left flip), and the on-screen windows as `(layer, bounds)` pairs,
    /// returns true when a normal-level (layer 0) window reaches the screen's
    /// 3pt top band AND spans at least 80% of its width — a fullscreen Space, or
    /// a maximized window under a hidden menu bar. Deterministic and free of
    /// AppKit/CoreGraphics globals so it can be exercised against synthetic
    /// window lists (issue #25).
    nonisolated static func coversNotchTopBand(
        notchScreenFrame: CGRect,
        primaryScreenFrame: CGRect,
        windows: [(layer: Int, bounds: CGRect)]
    ) -> Bool {
        // The screen's top edge in CGWindow global (top-left origin) coordinates,
        // widened to a 3pt band to tolerate sub-pixel/rounding at the very top.
        let topBand = CGRect(
            x: notchScreenFrame.minX,
            y: primaryScreenFrame.maxY - notchScreenFrame.maxY,
            width: notchScreenFrame.width,
            height: 3
        )
        for window in windows where window.layer == 0 {
            // Must reach the top edge AND cover most of the width — a small window
            // parked at the top must not count as fullscreen.
            if window.bounds.intersects(topBand),
               window.bounds.width >= notchScreenFrame.width * 0.8 {
                return true
            }
        }
        return false
    }
}
