import Foundation
import IOKit

final class ThermalCollector: MetricCollector {
    typealias Output = ThermalStatus

    func collect() async throws -> ThermalStatus {
        var cpuTemp: Double = 0.0
        var gpuTemp: Double = 0.0
        var batteryTemp: Double = 0.0
        var fanSpeed: Int = 0
        var fanCount: Int = 0
        var systemPower: Double = 0.0
        var adapterPower: Double = 0.0
        var batteryPower: Double = 0.0

        // Get CPU temperature from IOKit
        if let cpuService = IOKitHelper.getService(name: "IOPlatformSensorFamily") {
            defer { IOKitHelper.release(cpuService) }

            // Try to get CPU temperature
            if let temp: Int = IOKitHelper.getProperty(cpuService, key: "temperature") {
                cpuTemp = Double(temp) / 100.0 // Convert to Celsius
            }
        }

        // Get GPU temperature (similar approach)
        if let gpuService = IOKitHelper.getService(name: "IOAccelerator") {
            defer { IOKitHelper.release(gpuService) }

            if let temp: Int = IOKitHelper.getProperty(gpuService, key: "temperature") {
                gpuTemp = Double(temp) / 100.0 // Convert to Celsius
            }
        }

        // Get battery temperature from AppleSmartBattery
        if let batteryService = IOKitHelper.getService(name: "AppleSmartBattery") {
            defer { IOKitHelper.release(batteryService) }

            if let tempData = IOKitHelper.propertyGetData(batteryService, key: "Temperature") {
                if tempData.count == MemoryLayout<UInt16>.size {
                    let tempValue = tempData.withUnsafeBytes { $0.load(as: UInt16.self) }
                    batteryTemp = Double(tempValue) / 10.0 // Convert from deci-degrees to degrees
                }
            }
        }

        // Get fan information from AppleSMC
        if let smcService = IOKitHelper.getService(name: "AppleSMC") {
            defer { IOKitHelper.release(smcService) }

            // Try to get fan count and speed
            if let fans: [String: Any] = IOKitHelper.getProperty(smcService, key: "FAN") {
                fanCount = fans.count
                // Get current fan speed (first fan)
                if let fanData = fans.first?.value as? [String: Any],
                   let speed = fanData["speed"] as? Int {
                    fanSpeed = speed
                }
            }
        }

        // Get power information from IOPowerSources
        if let powerInfo = IOKitHelper.getPowerSourceInfo() {
            // Get power usage data
            if let powerData = powerInfo["Power Source State"] as? String {
                if powerData == "AC Power" {
                    adapterPower = 1.0 // Placeholder
                } else {
                    batteryPower = 1.0 // Placeholder
                }
            }
            systemPower = adapterPower + batteryPower
        }

        return ThermalStatus(
            cpuTemp: cpuTemp,
            gpuTemp: gpuTemp,
            batteryTemp: batteryTemp,
            fanSpeed: fanSpeed,
            fanCount: fanCount,
            systemPower: systemPower,
            adapterPower: adapterPower,
            batteryPower: batteryPower
        )
    }
}