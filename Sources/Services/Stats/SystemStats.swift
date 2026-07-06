import Foundation

/// A snapshot of live system load for the notch stats activity.
struct SystemStats: Equatable {
    var cpu: Double            // 0…1
    var memoryUsed: UInt64     // bytes
    var memoryTotal: UInt64    // bytes
    var networkDown: Double    // bytes/sec
    var networkUp: Double      // bytes/sec

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }

    /// Compact "12.3 GB" style formatter for memory.
    static func formatBytes(_ bytes: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .memory
        return f.string(fromByteCount: Int64(bytes))
    }

    /// Compact "1.2 MB/s" style formatter for network rate.
    static func formatRate(_ bytesPerSec: Double) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .decimal
        return f.string(fromByteCount: Int64(max(0, bytesPerSec))) + "/s"
    }
}
