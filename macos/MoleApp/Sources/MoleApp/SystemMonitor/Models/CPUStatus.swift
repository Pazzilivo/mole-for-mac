import Foundation

// CPUStatus
struct CPUStatus: Codable {
    let usage: Double
    let perCore: [Double]
    let perCoreEstimated: Bool
    let load1: Double
    let load5: Double
    let load15: Double
    let coreCount: Int
    let logicalCPU: Int
    let pCoreCount: Int
    let eCoreCount: Int

    enum CodingKeys: String, CodingKey {
        case usage
        case perCore = "per_core"
        case perCoreEstimated = "per_core_estimated"
        case load1
        case load5
        case load15
        case coreCount = "core_count"
        case logicalCPU = "logical_cpu"
        case pCoreCount = "p_core_count"
        case eCoreCount = "e_core_count"
    }
}