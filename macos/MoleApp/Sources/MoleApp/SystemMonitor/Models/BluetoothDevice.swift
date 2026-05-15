import Foundation

// BluetoothDevice
struct BluetoothDevice: Codable {
    let name: String
    let connected: Bool
    let battery: String
}