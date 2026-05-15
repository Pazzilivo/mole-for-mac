import Foundation
import IOKit.ps

final class BatteryCollector: MetricCollector {
    typealias Output = [BatteryStatus]

    func collect() async throws -> [BatteryStatus] {
        var batteries: [BatteryStatus] = []

        // Check if battery exists
        guard let service = IOKitHelper.getService(name: "AppleSmartBattery") else {
            return [] // No battery (desktop Mac)
        }

        defer {
            IOKitHelper.release(service)
        }

        // Get battery properties
        func getBatteryProperty(_ key: String) -> Any? {
            let cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key, CFStringGetSystemEncoding())
            return IORegistryEntryCreateCFProperty(service, cfKey, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        // Get current capacity percentage
        var percent: Double = 0.0
        if let currentCapacity = getBatteryProperty("CurrentCapacity") as? Int,
           let maxCapacity = getBatteryProperty("MaxCapacity") as? Int,
           maxCapacity > 0 {
            percent = Double(currentCapacity) / Double(maxCapacity) * 100.0
        }

        // Get charging status
        var isCharging = false
        var externalConnected = false
        if let plugged = getBatteryProperty("ExternalConnected") as? Bool {
            externalConnected = plugged
        }
        if let charging = getBatteryProperty("IsCharging") as? Bool {
            isCharging = charging
        }

        // Get time remaining
        var timeLeft = "Unknown"
        if let timeRemaining = getBatteryProperty("TimeRemaining") as? Int {
            if timeRemaining >= 0 {
                let hours = timeRemaining / 60
                let minutes = timeRemaining % 60
                timeLeft = "\(hours)h \(minutes)m"
            } else if isCharging {
                timeLeft = "Calculating..."
            }
        }

        // Get cycle count
        var cycleCount: Int = 0
        if let cycles = getBatteryProperty("CycleCount") as? Int {
            cycleCount = cycles
        }

        // Get capacity health
        var capacity: Int = 100
        if let maxCap = getBatteryProperty("MaxCapacity") as? Int,
           let designCap = getBatteryProperty("DesignCapacity") as? Int,
           designCap > 0 {
            capacity = Int((Double(maxCap) / Double(designCap)) * 100.0)
        }

        // Determine health status
        let health: String
        if capacity < 80 || cycleCount > 900 {
            health = "Service Soon"
        } else if capacity < 90 || cycleCount > 500 {
            health = "Fair"
        } else {
            health = "Normal"
        }

        // Determine charging status string
        let status: String
        if isCharging && externalConnected {
            status = "Charging"
        } else if externalConnected {
            status = "Full"
        } else {
            status = "Discharging"
        }

        let battery = BatteryStatus(
            percent: percent,
            status: status,
            timeLeft: timeLeft,
            health: health,
            cycleCount: cycleCount,
            capacity: capacity
        )

        batteries.append(battery)
        return batteries
    }
}