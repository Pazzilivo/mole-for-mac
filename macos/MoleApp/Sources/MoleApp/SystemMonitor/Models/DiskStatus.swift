import Foundation

// DiskStatus
struct DiskStatus: Codable {
    let mount: String
    let device: String
    let used: UInt64
    let total: UInt64
    let usedPercent: Double
    let fstype: String
    let external: Bool

    enum CodingKeys: String, CodingKey {
        case mount
        case device
        case used
        case total
        case usedPercent = "used_percent"
        case fstype
        case external
    }
}