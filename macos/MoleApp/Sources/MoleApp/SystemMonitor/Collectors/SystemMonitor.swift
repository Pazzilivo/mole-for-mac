import Foundation
import SwiftUI

@MainActor
final class SystemMonitor: ObservableObject {
    private let hardwareCollector: HardwareCollector
    private let cpuCollector: CPUCollector
    private let memoryCollector: MemoryCollector
    private let diskCollector: DiskCollector
    private let batteryCollector: BatteryCollector
    private let gpuCollector: GPUCollector
    private let networkCollector: NetworkCollector
    private let bluetoothCollector: BluetoothCollector
    private let processCollector: ProcessCollector
    private let thermalCollector: ThermalCollector
    private let diskIOCollector: DiskIOCollector

    init(
        hardwareCollector: HardwareCollector = HardwareCollector(),
        cpuCollector: CPUCollector = CPUCollector(),
        memoryCollector: MemoryCollector = MemoryCollector(),
        diskCollector: DiskCollector = DiskCollector(),
        batteryCollector: BatteryCollector = BatteryCollector(),
        gpuCollector: GPUCollector = GPUCollector(),
        networkCollector: NetworkCollector = NetworkCollector(),
        bluetoothCollector: BluetoothCollector = BluetoothCollector(),
        processCollector: ProcessCollector = ProcessCollector(),
        thermalCollector: ThermalCollector = ThermalCollector(),
        diskIOCollector: DiskIOCollector = DiskIOCollector()
    ) {
        self.hardwareCollector = hardwareCollector
        self.cpuCollector = cpuCollector
        self.memoryCollector = memoryCollector
        self.diskCollector = diskCollector
        self.batteryCollector = batteryCollector
        self.gpuCollector = gpuCollector
        self.networkCollector = networkCollector
        self.bluetoothCollector = bluetoothCollector
        self.processCollector = processCollector
        self.thermalCollector = thermalCollector
        self.diskIOCollector = diskIOCollector
    }

    func collect() async throws -> SystemMetrics {
        // Collect all system metrics in parallel for better performance
        async let cpu = cpuCollector.collect()
        async let memory = memoryCollector.collect()
        async let disks = diskCollector.collect()
        async let batteries = batteryCollector.collect()
        async let gpu = gpuCollector.collect()
        async let network = networkCollector.collect()
        async let bluetooth = bluetoothCollector.collect()
        async let topProcesses = processCollector.collect()
        async let thermal = thermalCollector.collect()
        async let diskIO = diskIOCollector.collect()

        // Wait for all collectors to complete
        let cpuResult = try await cpu
        let memoryResult = try await memory
        let diskMetrics = try await disks
        let batteryMetrics = try await batteries
        let gpuResult = try await gpu
        let networkResult = try await network
        let bluetoothResult = try await bluetooth
        let processEntries = try await topProcesses
        let thermalResult = try await thermal
        let diskIOResult = try await diskIO

        // Calculate uptime
        let uptime = getUptime()

        // Calculate trash size (use first disk or 0)
        let trashSize: UInt64 = 0 // Would need to be calculated separately

        // Get host information
        let host = getHostname()

        // Get hardware info with proper RAM and disk size
        let mainDisk = diskMetrics.first(where: { !$0.external }) ?? diskMetrics.first
        let totalRAM = memoryResult.total
        let diskSize = mainDisk?.total ?? 0

        // Get hardware with proper values
        let hardwareWithSpecs = hardwareCollector.collect(totalRAM: totalRAM, diskSize: diskSize)

        // Calculate health score
        let (healthScore, healthScoreMsg) = HealthCalculator.calculate(
            cpuUsage: cpuResult.usage,
            memoryUsedPercent: memoryResult.usedPercent,
            diskUsedPercent: mainDisk?.usedPercent ?? 0.0,
            batteryTemp: thermalResult.batteryTemp,
            diskReadRate: diskIOResult.readRate,
            memoryPressure: memoryResult.pressure,
            batteryCycleCount: batteryMetrics.first?.cycleCount ?? 0,
            batteryCapacity: batteryMetrics.first?.capacity ?? 100,
            uptimeSeconds: uptime
        )

        return SystemMetrics(
            collectedAt: Date(),
            host: host,
            platform: "macos",
            uptime: FormatHelper.formatUptime(uptime),
            uptimeSeconds: uptime,
            procs: UInt64(processEntries.count),
            hardware: hardwareWithSpecs,
            healthScore: healthScore,
            healthScoreMsg: healthScoreMsg,
            cpu: cpuResult,
            gpu: gpuResult,
            memory: memoryResult,
            disks: diskMetrics,
            trashSize: trashSize,
            trashApprox: false,
            diskIO: diskIOResult,
            network: networkResult,
            networkHistory: [], // TODO: Implement historical data collection
            proxyStatus: nil,   // TODO: Implement proxy detection
            batteries: batteryMetrics,
            thermal: thermalResult,
            sensors: [],        // TODO: Implement sensor reading collection
            bluetooth: bluetoothResult,
            topProcesses: processEntries,
            processWatchConfig: [], // TODO: Implement process watch configuration
            processAlerts: []       // TODO: Implement process alerting
        )
    }

    private func getHostname() -> String {
        var hostname = [CChar](repeating: 0, count: 256)
        gethostname(&hostname, 255)
        return String(cString: hostname)
    }

    private func getUptime() -> UInt64 {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &bootTime, &size, nil, 0)

        var now = timeval()
        let currentTime = Date().timeIntervalSince1970
        now.tv_sec = Int(currentTime)
        now.tv_usec = 0
        var uptime = now.tv_sec - bootTime.tv_sec
        if uptime < 0 {
            uptime = 0
        }

        return UInt64(uptime)
    }
}