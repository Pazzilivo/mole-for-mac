import Foundation

final class CPUCollector: MetricCollector {
    typealias Output = CPUStatus

    private var previousCPUTicks: [Int32]?
    private var previousCoreCount: Int = 0

    func collect() async throws -> CPUStatus {
        // Get core counts
        let coreCount = Int(SysctlHelper.getInt32("hw.physicalcpu") ?? 0)
        let logicalCPU = Int(SysctlHelper.getInt32("hw.logicalcpu") ?? 0)

        // Get P/E core counts (Apple Silicon)
        var pCoreCount: Int = 0
        var eCoreCount: Int = 0
        if let pCores = SysctlHelper.getInt32("hw.perflevel0.logicalcpu") {
            pCoreCount = Int(pCores)
        }
        if let eCores = SysctlHelper.getInt32("hw.perflevel1.logicalcpu") {
            eCoreCount = Int(eCores)
        }

        // First sampling
        let (firstCPUTicks, firstCoreCount) = try getProcessorInfo()
        previousCPUTicks = firstCPUTicks
        previousCoreCount = firstCoreCount

        // Wait 100ms for delta calculation
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Second sampling
        let (secondCPUTicks, secondCoreCount) = try getProcessorInfo()

        // Calculate per-core usage
        var perCore: [Double] = []
        if let previous = previousCPUTicks,
           secondCoreCount == previousCoreCount {
            for core in 0..<secondCoreCount {
                let coreUsage = calculateCoreUsage(
                    previous: previous,
                    current: secondCPUTicks,
                    core: core
                )
                perCore.append(coreUsage)
            }
        } else {
            // Fallback: fill with zeros
            for _ in 0..<secondCoreCount {
                perCore.append(0.0)
            }
        }

        // Calculate average usage
        let avgUsage = perCore.isEmpty ? 0.0 : perCore.reduce(0, +) / Double(perCore.count)

        // Get load averages
        var loadAvg = [Double](repeating: 0, count: 3)
        let loadResult = getloadavg(&loadAvg, 3)
        let load1 = loadResult >= 1 ? loadAvg[0] : 0.0
        let load5 = loadResult >= 2 ? loadAvg[1] : 0.0
        let load15 = loadResult >= 3 ? loadAvg[2] : 0.0

        return CPUStatus(
            usage: avgUsage,
            perCore: perCore,
            perCoreEstimated: false,
            load1: load1,
            load5: load5,
            load15: load15,
            coreCount: coreCount,
            logicalCPU: logicalCPU,
            pCoreCount: pCoreCount,
            eCoreCount: eCoreCount
        )
    }

    private func getProcessorInfo() throws -> ([Int32], Int) {
        var numCpu: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpu,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS else {
            throw NSError(domain: "MachError", code: Int(result), userInfo: nil)
        }

        defer {
            if let info = cpuInfo {
                vm_deallocate(
                    mach_task_self_,
                    vm_address_t(bitPattern: Int(bitPattern: info)),
                    vm_size_t(Int(numCpuInfo) * MemoryLayout<Int32>.size)
                )
            }
        }

        // Convert to array of Int32
        var ticks: [Int32] = []
        if let info = cpuInfo {
            for i in 0..<Int(numCpuInfo) {
                ticks.append(info[i])
            }
        }

        return (ticks, Int(numCpu))
    }

    private func calculateCoreUsage(previous: [Int32], current: [Int32], core: Int) -> Double {
        let CPU_STATE_MAX = 4
        let coreOffset = core * CPU_STATE_MAX

        guard coreOffset + CPU_STATE_MAX <= current.count,
              coreOffset + CPU_STATE_MAX <= previous.count else {
            return 0.0
        }

        // CPU states: USER, SYSTEM, IDLE, NICE
        // FIXED C1: Use current values for the current state, not previous
        let currentUser = Double(current[coreOffset + 0])
        let currentSystem = Double(current[coreOffset + 1])
        let currentIdle = Double(current[coreOffset + 2])
        let currentNice = Double(current[coreOffset + 3])

        let previousUser = Double(previous[coreOffset + 0])
        let previousSystem = Double(previous[coreOffset + 1])
        let previousIdle = Double(previous[coreOffset + 2])
        let previousNice = Double(previous[coreOffset + 3])

        let totalDelta = (currentUser + currentSystem + currentIdle + currentNice) -
                        (previousUser + previousSystem + previousIdle + previousNice)

        guard totalDelta > 0 else {
            return 0.0
        }

        let activeDelta = (currentUser + currentSystem) - (previousUser + previousSystem)
        return (activeDelta / totalDelta) * 100.0
    }
}