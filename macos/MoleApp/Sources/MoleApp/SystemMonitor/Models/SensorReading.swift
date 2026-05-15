import Foundation

struct SensorReading: Codable {
    let sensorName: String
    let sensorType: SensorType
    let currentValue: Double
    let unit: String
    let min: Double?
    let max: Double?
    let warningThreshold: Double?
    let criticalThreshold: Double?

    enum SensorType: String, Codable {
        case temperature = "TEMPERATURE"
        case voltage = "VOLTAGE"
        case current = "CURRENT"
        case power = "POWER"
        case fan = "FAN"
        case humidity = "HUMIDITY"
        case other = "OTHER"
    }

    enum CodingKeys: String, CodingKey {
        case sensorName = "sensor_name"
        case sensorType = "sensor_type"
        case currentValue = "current_value"
        case unit
        case min
        case max
        case warningThreshold = "warning_threshold"
        case criticalThreshold = "critical_threshold"
    }
}