import Foundation

struct ProcessWatchConfig: Codable {
    let processName: String
    let enabled: Bool
    let cpuThreshold: Double?    // CPU usage percentage threshold
    let memoryThreshold: Double? // Memory usage percentage threshold
    let checkInterval: Int       // Check interval in seconds
    let alertOnExit: Bool        // Alert when process exits
    let alertOnLaunch: Bool      // Alert when process launches
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case processName = "process_name"
        case enabled
        case cpuThreshold = "cpu_threshold"
        case memoryThreshold = "memory_threshold"
        case checkInterval = "check_interval"
        case alertOnExit = "alert_on_exit"
        case alertOnLaunch = "alert_on_launch"
        case notes
    }
}