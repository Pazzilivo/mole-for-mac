import Foundation

struct FormatHelper {
    /// Format bytes to human readable string
    static func humanBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Format bytes to human readable string (optional)
    static func humanBytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "Unknown" }
        return humanBytes(bytes)
    }

    /// Format uptime seconds to human readable string
    static func formatUptime(_ seconds: UInt64) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}