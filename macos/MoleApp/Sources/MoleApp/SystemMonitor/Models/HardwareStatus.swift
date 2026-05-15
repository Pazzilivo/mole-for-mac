import Foundation

// HardwareStatus
struct HardwareStatus: Codable {
    let model: String
    let cpuModel: String
    let totalRAM: String
    let diskSize: String
    let osVersion: String
    let refreshRate: String

    enum CodingKeys: String, CodingKey {
        case model
        case cpuModel = "cpu_model"
        case totalRAM = "total_ram"
        case diskSize = "disk_size"
        case osVersion = "os_version"
        case refreshRate = "refresh_rate"
    }
}