import AppKit
import Combine

/// Applies settings-driven system side-effects: launch-at-login, hide from
/// screen capture, and hide while a fullscreen app is frontmost.
@MainActor
final class EffectsController {
    private let settings: SettingsStore
    private weak var panel: NSPanel?
    private weak var model: NotchViewModel?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsStore, panel: NSPanel?, model: NotchViewModel? = nil) {
        self.settings = settings
        self.panel = panel
        self.model = model
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
                guard let self, let panel = self.panel else { return }
                if on { self.refreshFullscreenState() } else { panel.animator().alphaValue = 1 }
            }
            .store(in: &cancellables)
        refreshFullscreenState()
    }

    /// Re-evaluates fullscreen for the panel's current screen. Called by
    /// AppDelegate after the panel moves to another display.
    func refresh() { refreshFullscreenState() }

    @objc private func refreshFullscreenState() {
        applyFullscreenState()
        // The Space-change notification fires while the fullscreen transition is
        // still animating — window bounds and the menu bar haven't settled — so
        // sample once more after the animation is over.
        settleRecheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyFullscreenState() }
        settleRecheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
    private var settleRecheck: DispatchWorkItem?

    private func applyFullscreenState() {
        let fullscreen = isFullscreenSpaceActive()
        // Only publish real transitions — this fires on every app switch, and a
        // same-value set would still invalidate the whole notch view tree.
        if let model, model.fullscreenActive != fullscreen {
            model.fullscreenActive = fullscreen
        }
        guard settings.hideInFullscreen, let panel else { return }
        panel.animator().alphaValue = fullscreen ? 0 : 1
    }

    /// Whether window content on the notch's own screen can reach the top edge
    /// (a fullscreen Space, or a maximized window under a hidden menu bar) —
    /// exactly the situations where the resting notch would cover it.
    private func isFullscreenSpaceActive() -> Bool {
        guard let screen = panel?.screen ?? NSScreen.main,
              let primary = NSScreen.screens.first else { return false }
        // The menu bar reserves the top of `visibleFrame` whenever it's showing
        // on this screen; only a fullscreen Space (or a hidden menu bar) lets
        // the visible frame reach the top edge.
        guard screen.visibleFrame.maxY >= screen.frame.maxY - 1 else { return false }

        // ...and require actual window content up there. A fullscreen app can be
        // several stacked CG windows (e.g. Chrome's tab strip above its content
        // view), none of them screen-height, so look for any normal-level window
        // touching the screen's top band rather than one full-height window.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // CGWindow bounds are global top-left-origin; flip the screen's top band
        // (AppKit bottom-left-origin) into that space before comparing.
        let topBand = CGRect(
            x: screen.frame.minX,
            y: primary.frame.maxY - screen.frame.maxY,
            width: screen.frame.width,
            height: 2
        )
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if bounds.intersects(topBand) { return true }
        }
        return false
    }
}
