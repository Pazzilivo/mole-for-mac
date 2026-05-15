import Foundation
import CoreGraphics

final class HardwareCollector: MetricCollector {
    typealias Output = HardwareStatus

    private var cache: HardwareStatus?
    private var cacheTime: Date = .distantPast
    private let cacheTTL: TimeInterval = 600 // 10 minutes

    private let marketingNameMap: [String: String] = [
        // MacBook Air
        "Mac14,2": "MacBook Air 15-inch, M2, 2023",
        "Mac14,15": "MacBook Air 15-inch, M3, 2024",

        // MacBook Pro
        "Mac14,5": "MacBook Pro 14-inch, M2 Pro, 2023",
        "Mac14,6": "MacBook Pro 16-inch, M2 Pro, 2023",
        "Mac14,7": "MacBook Pro 14-inch, M2 Max, 2023",
        "Mac14,8": "MacBook Pro 16-inch, M2 Max, 2023",
        "Mac14,9": "MacBook Pro 14-inch, M2 Max, 2023",
        "Mac14,10": "MacBook Pro 16-inch, M2 Max, 2023",
        "Mac15,3": "MacBook Pro 14-inch, M3, 2023",
        "Mac15,6": "MacBook Pro 16-inch, M3 Pro, 2023",
        "Mac15,7": "MacBook Pro 14-inch, M3 Max, 2023",
        "Mac15,8": "MacBook Pro 16-inch, M3 Max, 2023",
        "Mac15,9": "MacBook Pro 14-inch, M3 Max, 2023",
        "Mac15,10": "MacBook Pro 16-inch, M3 Max, 2023",

        // Mac mini
        "Mac14,3": "Mac mini, M2, 2023",
        "Mac14,12": "Mac mini, M2 Pro, 2023",

        // Mac Studio
        "Mac13,1": "Mac Studio, M1 Max, 2022",
        "Mac13,2": "Mac Studio, M1 Ultra, 2022",
        "Mac13,3": "Mac Studio, M2 Max, 2023",
        "Mac13,4": "Mac Studio, M2 Ultra, 2023",
        "Mac14,13": "Mac Studio, M2 Max, 2023",
        "Mac14,14": "Mac Studio, M2 Ultra, 2023",

        // iMac
        "Mac15,4": "iMac 24-inch, M3, 2023",
        "Mac15,5": "iMac 24-inch, M3, 2023",

        // Apple Silicon from hw.product
        "J314sAP": "MacBook Pro 14-inch, M1 Pro, 2021",
        "J316sAP": "MacBook Pro 16-inch, M1 Pro, 2021",
        "J314cAP": "MacBook Pro 14-inch, M1 Max, 2021",
        "J316cAP": "MacBook Pro 16-inch, M1 Max, 2021",
        "J274sAP": "Mac mini, M1, 2020",
        "J275cAP": "Mac mini, M1, 2020",
        "J274cAP": "Mac mini, M1, 2020"
    ]

    func collect(totalRAM: UInt64, diskSize: UInt64) -> HardwareStatus {
        // Check cache
        if let cached = cache,
           Date().timeIntervalSince(cacheTime) < cacheTTL {
            return cached
        }

        let status = HardwareStatus(
            model: getModelName(),
            cpuModel: getCPUModel(),
            totalRAM: FormatHelper.humanBytes(totalRAM),
            diskSize: FormatHelper.humanBytes(diskSize),
            osVersion: getOSVersion(),
            refreshRate: String(format: "%.0fHz", getRefreshRate() ?? 60)
        )

        // Update cache
        cache = status
        cacheTime = Date()

        return status
    }

    func collect() async throws -> HardwareStatus {
        // Get actual total RAM and disk size
        let totalRAM = SysctlHelper.getUInt64("hw.memsize") ?? 0
        let diskSize = getDiskSize() ?? 0
        return collect(totalRAM: totalRAM, diskSize: diskSize)
    }

    private func getDiskSize() -> UInt64? {
        // Get disk size using FileManager
        let fileManager = FileManager.default
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: "/")
            if let diskSize = attributes[.systemSize] as? UInt64 {
                return diskSize
            }
        } catch {
            return nil
        }
        return nil
    }

    private func getModelName() -> String {
        if let model = SysctlHelper.getString("hw.model") {
            return marketingNameMap[model] ?? model
        }
        return "Unknown Mac"
    }

    private func getCPUModel() -> String {
        // Try Apple Silicon first
        if let product = SysctlHelper.getString("hw.product") {
            return marketingNameMap[product] ?? product
        }

        // Fallback to Intel
        if let cpuModel = SysctlHelper.getString("machdep.cpu.brand_string") {
            return cpuModel
        }

        return "Unknown CPU"
    }

    private func getOSVersion() -> String {
        let processInfo = ProcessInfo.processInfo
        let version = processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }

    private func getRefreshRate() -> Double? {
        let mainDisplayID = CGMainDisplayID()
        guard let displayMode = CGDisplayCopyDisplayMode(mainDisplayID) else {
            return nil
        }

        let refreshRate = displayMode.refreshRate
        return refreshRate > 0 ? refreshRate : nil
    }
}