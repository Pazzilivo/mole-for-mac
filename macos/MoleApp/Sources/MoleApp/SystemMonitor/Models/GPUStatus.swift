import Foundation

// GPUStatus
struct GPUStatus: Codable {
    let name: String
    let usage: Double
    let memoryUsed: Double
    let memoryTotal: Double
    let coreCount: Int
    let note: String

    enum CodingKeys: String, CodingKey {
        case name
        case usage
        case memoryUsed = "memory_used"
        case memoryTotal = "memory_total"
        case coreCount = "core_count"
        case note
    }
}