import Foundation

// MemoryStatus
struct MemoryStatus: Codable {
    let used: UInt64
    let total: UInt64
    let usedPercent: Double
    let swapUsed: UInt64
    let swapTotal: UInt64
    let cached: UInt64
    let pressure: String

    enum CodingKeys: String, CodingKey {
        case used
        case total
        case usedPercent = "used_percent"
        case swapUsed = "swap_used"
        case swapTotal = "swap_total"
        case cached
        case pressure
    }
}