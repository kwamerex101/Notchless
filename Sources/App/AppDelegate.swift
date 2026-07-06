import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = NotchViewModel()

    private var panel: NotchPanel?
    private var mouseTracker: NotchMouseTracker?
    private let panelSize = NSSize(width: 760, height: 460)

    private lazy var media = MediaController(model: model)
    private lazy var hud = HUDController(model: model)
    private lazy var calendar = CalendarController(model: model)
    private lazy var notifications = NotificationsController(model: model)
    private(set) lazy var dictation = DictationController(model: model)
    private var effects: EffectsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()

        // Permission-free services start immediately.
        media.start()
        effects = EffectsController(settings: model.settings, panel: panel)
        effects?.start()

        // Services that trigger system permission prompts wait until the user
        // has been primed by onboarding (or it's already been completed).
        OnboardingWindowController.shared.presentIfNeeded { [weak self] in
            self?.startPermissionedServices()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    private func startPermissionedServices() {
        hud.start()
        calendar.start()
        notifications.start()
        dictation.start()
    }

    private func makeRootView(_ metrics: NotchMetrics) -> NotchRootView {
        NotchRootView(
            model: model,
            metrics: metrics,
            onCommand: { [weak self] cmd in self?.media.send(cmd) },
            onOpenSettings: { SettingsWindowController.shared.show() }
        )
    }

    private func buildPanel() {
        guard let screen = targetScreen() else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        let frame = panelFrame(for: metrics)

        DebugRender.run(metrics: metrics)  // no-op unless DI_DEBUG_RENDER is set
        let panel = NotchPanel(contentRect: frame)
        let host = NotchHostingView(rootView: makeRootView(metrics), model: model, metrics: metrics)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel

        let tracker = NotchMouseTracker(panel: panel, model: model, metrics: metrics)
        tracker.start()
        self.mouseTracker = tracker
    }

    private func targetScreen() -> NSScreen? {
        switch model.settings.simulatedDisplay {
        case .builtIn:
            return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        case .active:
            return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        case .main:
            return NSScreen.main
        }
    }

    private func panelFrame(for metrics: NotchMetrics) -> NSRect {
        NSRect(
            x: metrics.notchCenterX - panelSize.width / 2,
            y: metrics.screenTopY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        media.stop()
    }

    @objc private func screensChanged() {
        guard let panel, let screen = targetScreen() else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        panel.setFrame(panelFrame(for: metrics), display: true)
        if let host = panel.contentView as? NotchHostingView {
            host.metrics = metrics
            host.rootView = makeRootView(metrics)
        }
        mouseTracker?.metrics = metrics
    }
}
