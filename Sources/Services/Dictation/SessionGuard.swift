/// A generation token guarding against stale async writes. Each new dictation
/// session calls `begin()`; any in-flight task from a prior session captures its
/// generation and checks `isCurrent(_:)` before writing shared state, so a
/// re-press mid-transcription can't have the old task stomp the new session.
struct SessionGuard {
    private(set) var current: Int = 0

    mutating func begin() -> Int {
        current += 1
        return current
    }

    func isCurrent(_ generation: Int) -> Bool {
        generation == current
    }
}
