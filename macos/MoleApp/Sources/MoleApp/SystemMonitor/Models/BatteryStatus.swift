import Foundation

// BatteryStatus
struct BatteryStatus: Codable {
    let percent: Double
    let status: String
    let timeLeft: String
    let health: String
    let cycleCount: Int
    let capacity: Int

    enum CodingKeys: String, CodingKey {
        case percent
        case status
        case timeLeft = "time_left"
        case health
        case cycleCount = "cycle_count"
        case capacity
    }
}