import Foundation

final class MemoryCollector: MetricCollector {
    typealias Output = MemoryStatus

    func collect() async throws -> MemoryStatus {
        // Get total memory
        guard let total = SysctlHelper.getUInt64("hw.memsize") else {
            throw NSError(domain: "MemoryCollector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get total memory"])
        }

        // Get VM stats
        let vmStats = try getVMStats()
        let pageSize = UInt64(vm_kernel_page_size)

        // Calculate memory usage
        let free = UInt64(vmStats.free_count) * pageSize
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let speculative = UInt64(vmStats.speculative_count) * pageSize
        let external = UInt64(vmStats.external_page_count) * pageSize // file-backed

        // Used calculation aligned with gopsutil
        let used = active + wired + speculative // Not including external (file-backed)

        let usedPercent = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0

        // Get swap usage
        let (swapUsed, swapTotal) = try getSwapUsage()

        // Cached file-backed memory
        let cached = external

        // Get memory pressure
        let pressure = getMemoryPressure()

        return MemoryStatus(
            used: used,
            total: total,
            usedPercent: usedPercent,
            swapUsed: swapUsed,
            swapTotal: swapTotal,
            cached: cached,
            pressure: pressure
        )
    }

    private func getVMStats() throws -> vm_statistics64 {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw NSError(domain: "MachError", code: Int(result), userInfo: nil)
        }

        return vmStats
    }

    private func getSwapUsage() throws -> (UInt64, UInt64) {
        // FIXED C2: Use sysctlbyname directly with manual parsing instead of unreliable struct
        var size: Int = 0
        sysctlbyname("vm.swapusage", nil, &size, nil, 0)

        if size == 0 {
            return (0, 0)
        }

        // Create buffer to hold swap data
        var buffer = [UInt8](repeating: 0, count: size)
        let result = sysctlbyname("vm.swapusage", &buffer, &size, nil, 0)

        guard result == 0 else {
            return (0, 0) // Swap not available or error
        }

        // Parse swap data manually based on xsw_usage structure:
        // struct xsw_usage {
        //     uint64_t xsu_total;
        //     uint64_t xsu_used;
        //     uint32_t xsu_pagesize;
        //     boolean_t xsu_encrypted;
        // };

        // Add bounds check before accessing buffer
        guard buffer.count >= MemoryLayout<UInt64>.size * 2 else {
            return (0, 0)
        }

        let total = buffer.withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self)
        }
        let used = buffer.withUnsafeBytes { ptr in
            ptr.advanced(by: MemoryLayout<UInt64>.size).load(as: UInt64.self)
        }

        return (used, total)
    }

    private func getMemoryPressure() -> String {
        if let level = SysctlHelper.getInt32("kern.memorystatus_level") {
            if level >= 800 {
                return "normal"
            } else if level >= 400 {
                return "warn"
            } else {
                return "critical"
            }
        }
        return "unknown"
    }
}