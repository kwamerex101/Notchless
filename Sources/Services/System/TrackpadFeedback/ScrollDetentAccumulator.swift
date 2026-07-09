import Foundation

/// Velocity-aware scroll detent math. Pure value type — no clocks, no I/O —
/// timestamps come in as parameters so tests are deterministic.
///
/// Feel model: at rest, one tick per `baseThreshold` px (fine control). The
/// threshold widens linearly with scroll velocity, and above `flingCutoff`
/// ticks stop entirely — a fast fling feels like a smooth blur, not a rattle.
struct ScrollDetentAccumulator {
    let tuning: DetentTuning

    private var accumulated: Double = 0
    private var lastTimestamp: TimeInterval?
    private var lastDirection: Double = 0

    init(tuning: DetentTuning) {
        self.tuning = tuning
    }

    mutating func reset() {
        accumulated = 0
        lastTimestamp = nil
        lastDirection = 0
    }

    /// Feed one scroll event; returns how many detent ticks it produced.
    mutating func ticks(delta: Double, timestamp: TimeInterval) -> Int {
        guard delta != 0 else { return 0 }

        let direction: Double = delta > 0 ? 1 : -1
        let dt = lastTimestamp.map { timestamp - $0 }
        lastTimestamp = timestamp

        // New gesture after a quiet gap — don't let stale distance carry over.
        if let dt, dt > tuning.gestureGap {
            accumulated = 0
            lastDirection = 0
        }

        // Direction flip starts a fresh accumulation.
        if lastDirection != 0, direction != lastDirection {
            accumulated = 0
        }
        lastDirection = direction

        // Instantaneous velocity (px/s); first event of a gesture counts as 0.
        let velocity: Double
        if let dt, dt > 0, dt <= tuning.gestureGap {
            velocity = abs(delta) / dt
        } else {
            velocity = 0
        }

        // Flinging: suppress ticks and drop accumulated distance (the "blur").
        if velocity > tuning.flingCutoff {
            accumulated = 0
            return 0
        }

        let threshold = tuning.baseThreshold + velocity * tuning.velocityScale
        accumulated += abs(delta)
        let count = Int(accumulated / threshold)
        accumulated -= Double(count) * threshold
        return count
    }
}
