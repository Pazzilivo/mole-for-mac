import Foundation

// DiskIOStatus
struct DiskIOStatus: Codable {
    let readRate: Double
    let writeRate: Double

    enum CodingKeys: String, CodingKey {
        case readRate = "read_rate"
        case writeRate = "write_rate"
    }
}