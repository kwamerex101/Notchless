import AppKit

/// Drives a countdown timer, ticking `model.notchTimer` once a second. Registers
/// itself as `shared` so the expanded timer view can control it directly.
@MainActor
final class TimerController {
    private(set) static weak var shared: TimerController?

    private let model: NotchViewModel
    private var ticker: Timer?

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        Self.shared = self
    }

    func begin(seconds: Int) {
        guard seconds > 0 else { return }
        model.notchTimer = NotchTimerInfo(total: seconds, remaining: seconds, isRunning: true)
        startTicker()
    }

    func pause() {
        guard var timer = model.notchTimer else { return }
        timer.isRunning = false
        model.notchTimer = timer
        ticker?.invalidate()
    }

    func resume() {
        guard var timer = model.notchTimer, timer.remaining > 0 else { return }
        timer.isRunning = true
        model.notchTimer = timer
        startTicker()
    }

    func reset() {
        guard var timer = model.notchTimer else { return }
        timer.remaining = timer.total
        timer.isRunning = false
        model.notchTimer = timer
        ticker?.invalidate()
    }

    func cancel() {
        ticker?.invalidate()
        model.notchTimer = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard var timer = model.notchTimer, timer.isRunning else { return }
        timer.remaining = max(0, timer.remaining - 1)
        if timer.remaining == 0 {
            timer.isRunning = false
            ticker?.invalidate()
            NSSound(named: "Glass")?.play()
        }
        model.notchTimer = timer
    }
}
