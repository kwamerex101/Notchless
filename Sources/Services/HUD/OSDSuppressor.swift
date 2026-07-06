import AppKit

/// Best-effort suppression of the system volume/brightness OSD by pausing
/// `OSDUIHelper` while our own HUD is on screen, then resuming it. Uses
/// SIGSTOP/SIGCONT (reversible) rather than unloading the agent. Disabled by
/// default — intrusive and fragile across OS updates (see PLAN.md §5).
enum OSDSuppressor {
    /// Master switch. Off until validated on-device; flip to enable.
    static var enabled = false

    private static func pids() -> [pid_t] {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", "OSDUIHelper"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0) }
    }

    static func suppress() {
        guard enabled else { return }
        for pid in pids() { kill(pid, SIGSTOP) }
    }

    static func restore() {
        // Always safe to call; resumes anything we paused.
        for pid in pids() { kill(pid, SIGCONT) }
    }
}
