import Foundation

/// Abstracts the two raw OS operations `OSDSuppressor` needs, so its
/// state-machine logic (activate/deactivate/watchdog) can be unit-tested
/// without shelling out to `pgrep` or sending real signals.
protocol ProcessSignaller {
    /// PIDs of the named process (e.g. "OSDUIHelper"). Must be safe to call
    /// off the main thread — implementations should not touch UI state.
    func pids(ofProcessNamed name: String) -> [pid_t]
    /// Send a signal (SIGSTOP / SIGCONT) to a pid.
    func signal(_ sig: Int32, to pid: pid_t)
}

/// Production `ProcessSignaller`: shells out to `pgrep -x` to enumerate PIDs
/// and calls the raw `kill(2)` to signal them.
struct RealProcessSignaller: ProcessSignaller {
    func pids(ofProcessNamed name: String) -> [pid_t] {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", name]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0) }
    }

    func signal(_ sig: Int32, to pid: pid_t) {
        kill(pid, sig)
    }
}
