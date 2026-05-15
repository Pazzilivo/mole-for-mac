import Foundation

struct NetworkHistory: Codable {
    let timestamp: Date
    let interfaceName: String
    let rxRate: Double      // MB/s
    let txRate: Double      // MB/s
    let rxBandwidth: Double // Total bandwidth
    let txBandwidth: Double // Total bandwidth

    enum CodingKeys: String, CodingKey {
        case timestamp
        case interfaceName = "interface_name"
        case rxRate = "rx_rate"
        case txRate = "tx_rate"
        case rxBandwidth = "rx_bandwidth"
        case txBandwidth = "tx_bandwidth"
    }
}