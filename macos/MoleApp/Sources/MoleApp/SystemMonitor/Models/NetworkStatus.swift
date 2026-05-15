import Foundation

// NetworkStatus
struct NetworkStatus: Codable {
    let name: String
    let rxRateMBs: Double
    let txRateMBs: Double
    let ip: String

    enum CodingKeys: String, CodingKey {
        case name
        case rxRateMBs = "rx_rate_mbs"
        case txRateMBs = "tx_rate_mbs"
        case ip
    }
}