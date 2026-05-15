import Foundation

struct ProcessAlert: Codable {
    let id: String
    let processName: String
    let processId: Int?
    let alertType: AlertType
    let severity: AlertSeverity
    let message: String
    let timestamp: Date
    let acknowledged: Bool
    let resolved: Bool

    enum AlertType: String, Codable {
        case cpuThreshold = "CPU_THRESHOLD"
        case memoryThreshold = "MEMORY_THRESHOLD"
        case processExited = "PROCESS_EXITED"
        case processLaunched = "PROCESS_LAUNCHED"
        case processHung = "PROCESS_HUNG"
        case custom = "CUSTOM"
    }

    enum AlertSeverity: String, Codable {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case processName = "process_name"
        case processId = "process_id"
        case alertType = "alert_type"
        case severity
        case message
        case timestamp
        case acknowledged
        case resolved
    }
}