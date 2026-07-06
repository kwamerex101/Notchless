import AppKit
import Combine

/// Applies settings-driven system side-effects: launch-at-login, hide from
/// screen capture, and hide while a fullscreen app is frontmost.
@MainActor
final class EffectsController {
    private let settings: SettingsStore
    private weak var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(settings: SettingsStore, panel: NSPanel?) {
        self.settings = settings
        self.panel = panel
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

        // Hide while a fullscreen app is frontmost. Register unconditionally —
        // the handler gates on the live setting — so toggling the pref at
        // runtime takes effect without a relaunch.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        // When the user turns the pref off while the panel is hidden, bring it
        // back immediately (and re-evaluate when turned on).
        settings.$hideInFullscreen
            .sink { [weak self] on in
                guard let self, let panel = self.panel else { return }
                if on { self.activeSpaceChanged() } else { panel.animator().alphaValue = 1 }
            }
            .store(in: &cancellables)
    }

    @objc private func activeSpaceChanged() {
        guard settings.hideInFullscreen, let panel else { return }
        // A fullscreen app owns its own Space with no menu bar; approximate by
        // checking whether the frontmost window covers the whole screen.
        let fullscreen = isFrontmostAppFullscreen()
        panel.animator().alphaValue = fullscreen ? 0 : 1
    }

    private func isFrontmostAppFullscreen() -> Bool {
        guard let screen = NSScreen.main else { return false }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if bounds.height >= screen.frame.height { return true }
        }
        return false
    }
}
