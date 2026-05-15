import Foundation

// SystemMetrics - Top level snapshot
struct SystemMetrics: Codable {
    let collectedAt: Date
    let host: String
    let platform: String
    let uptime: String
    let uptimeSeconds: UInt64
    let procs: UInt64
    let hardware: HardwareStatus
    let healthScore: Int
    let healthScoreMsg: String
    let cpu: CPUStatus
    let gpu: [GPUStatus]
    let memory: MemoryStatus
    let disks: [DiskStatus]
    let trashSize: UInt64
    let trashApprox: Bool
    let diskIO: DiskIOStatus
    let network: [NetworkStatus]
    let networkHistory: [NetworkHistory]
    let proxyStatus: ProxyStatus?
    let batteries: [BatteryStatus]
    let thermal: ThermalStatus
    let sensors: [SensorReading]
    let bluetooth: [BluetoothDevice]
    let topProcesses: [ProcessEntry]
    let processWatchConfig: [ProcessWatchConfig]
    let processAlerts: [ProcessAlert]

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case host
        case platform
        case uptime
        case uptimeSeconds = "uptime_seconds"
        case procs
        case hardware
        case healthScore = "health_score"
        case healthScoreMsg = "health_score_msg"
        case cpu
        case gpu
        case memory
        case disks
        case trashSize = "trash_size"
        case trashApprox = "trash_approx"
        case diskIO = "disk_io"
        case network
        case networkHistory = "network_history"
        case proxyStatus = "proxy_status"
        case batteries
        case thermal
        case sensors
        case bluetooth
        case topProcesses = "top_processes"
        case processWatchConfig = "process_watch_config"
        case processAlerts = "process_alerts"
    }
}