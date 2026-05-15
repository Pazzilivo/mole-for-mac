import Foundation

struct HealthCalculator {
    /// Calculate health score (0-100) based on system metrics
    static func calculate(
        cpuUsage: Double,
        memoryUsedPercent: Double,
        diskUsedPercent: Double,
        batteryTemp: Double,
        diskReadRate: Double,
        memoryPressure: String,
        batteryCycleCount: Int,
        batteryCapacity: Int,
        uptimeSeconds: UInt64
    ) -> (score: Int, message: String) {
        // Weighted scoring (consistent with Go version)
        let cpuScore = componentScore(value: cpuUsage, normalThreshold: 30, highThreshold: 70)
        let memScore = componentScore(value: memoryUsedPercent, normalThreshold: 50, highThreshold: 80)
        let diskScore = componentScore(value: diskUsedPercent, normalThreshold: 70, highThreshold: 90)
        let thermalScore = componentScore(value: batteryTemp, normalThreshold: 60, highThreshold: 85)
        let ioScore = componentScore(value: diskReadRate, normalThreshold: 50, highThreshold: 150)

        var score = cpuScore * 30 + memScore * 25 + diskScore * 20 + thermalScore * 15 + ioScore * 10

        // Memory pressure penalty
        if memoryPressure == "warn" {
            score -= 5
        } else if memoryPressure == "critical" {
            score -= 15
        }

        // Battery penalty
        let (_, batteryPenalty) = batteryHealthLabel(cycles: batteryCycleCount, capacity: batteryCapacity)
        if batteryPenalty == "danger" {
            score -= 5
        } else if batteryPenalty == "warn" {
            score -= 2
        }

        // Uptime penalty
        let uptimeHours = Double(uptimeSeconds) / 3600
        if uptimeHours > 14 * 24 {
            score -= 3
        } else if uptimeHours > 7 * 24 {
            score -= 1
        }

        score = max(0, min(100, score))

        let message: String
        switch score {
        case 90...100:
            message = "Excellent"
        case 75..<90:
            message = "Good"
        case 60..<75:
            message = "Fair"
        case 40..<60:
            message = "Poor"
        default:
            message = "Critical"
        }

        return (Int(score), message)
    }

    private static func componentScore(value: Double, normalThreshold: Double, highThreshold: Double) -> Double {
        if value <= normalThreshold {
            return 1.0
        } else if value >= highThreshold {
            return 0.0
        } else {
            return 1.0 - (value - normalThreshold) / (highThreshold - normalThreshold)
        }
    }

    internal static func batteryHealthLabel(cycles: Int, capacity: Int) -> (String, String) {
        if cycles > 900 || capacity < 80 {
            return ("Service Soon", "danger")
        } else if cycles > 500 || capacity < 90 {
            return ("Fair", "warn")
        } else {
            return ("Healthy", "ok")
        }
    }
}