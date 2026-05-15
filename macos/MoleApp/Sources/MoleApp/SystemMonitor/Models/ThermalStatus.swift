import Foundation

// ThermalStatus
struct ThermalStatus: Codable {
    let cpuTemp: Double
    let gpuTemp: Double
    let batteryTemp: Double
    let fanSpeed: Int
    let fanCount: Int
    let systemPower: Double
    let adapterPower: Double
    let batteryPower: Double

    enum CodingKeys: String, CodingKey {
        case cpuTemp = "cpu_temp"
        case gpuTemp = "gpu_temp"
        case batteryTemp = "battery_temp"
        case fanSpeed = "fan_speed"
        case fanCount = "fan_count"
        case systemPower = "system_power"
        case adapterPower = "adapter_power"
        case batteryPower = "battery_power"
    }
}