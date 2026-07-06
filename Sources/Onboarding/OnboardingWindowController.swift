import AppKit
import SwiftUI

/// Owns the first-run onboarding window and reports when it finishes so the
/// permissioned services can start *after* the user has been primed.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var completion: (() -> Void)?
    private var didComplete = false

    private let completedKey = "hasCompletedOnboarding"

    var hasCompleted: Bool { UserDefaults.standard.bool(forKey: completedKey) }

    /// Presents onboarding if needed; calls `onComplete` when the user finishes
    /// (or has already completed it), so the caller can start its services.
    func presentIfNeeded(onComplete: @escaping () -> Void) {
        if hasCompleted {
            onComplete()
            return
        }
        completion = onComplete
        didComplete = false
        present()
    }

    /// Re-runs onboarding from Settings (does not gate services).
    func rerun() {
        completion = nil
        didComplete = false
        present()
    }

    private func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = OnboardingView(onFinish: { [weak self] in self?.finish() })
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.055, green: 0.06, blue: 0.078, alpha: 1)
        window.setContentSize(NSSize(width: 420, height: 620))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: completedKey)
        window?.close()
    }

    // Closing the window (via Done or the close button) completes onboarding and
    // releases the deferred services exactly once.
    func windowWillClose(_ notification: Notification) {
        window = nil
        guard !didComplete else { return }
        didComplete = true
        UserDefaults.standard.set(true, forKey: completedKey)
        let done = completion
        completion = nil
        done?()
    }
}
