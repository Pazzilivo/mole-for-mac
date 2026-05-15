import Foundation
import Metal
import IOKit

final class GPUCollector: MetricCollector {
    typealias Output = [GPUStatus]

    func collect() async throws -> [GPUStatus] {
        var gpus: [GPUStatus] = []

        // Get all Metal devices
        let devices = MTLCopyAllDevices()
        for device in devices {
            var name = device.name
            var memoryUsed: Double = 0.0
            var memoryTotal: Double = 0.0
            var coreCount: Int = 0
            var usage: Double = 0.0
            var note: String = ""

            // Get recommended memory size
            if #available(macOS 13.0, *) {
                memoryTotal = Double(device.recommendedMaxWorkingSetSize) / (1024.0 * 1024.0) // Convert to MB
            } else {
                memoryTotal = Double(device.maxBufferLength) / (1024.0 * 1024.0) // Convert to MB
            }

            // Get GPU name and additional info
            note = "Metal: \(device.name) - Registry ID: \(device.registryID)"

            // Try to get GPU core count for Apple Silicon
            if name.contains("Apple") {
                // Try to get core count from IOKit
                if let gpuService = IOKitHelper.getService(name: "AGXAccelerator") {
                    defer { IOKitHelper.release(gpuService) }

                    let gpuCores: Int? = IOKitHelper.getProperty(gpuService, key: "gpu_cores_count")
                    let altCores: Int? = IOKitHelper.getProperty(gpuService, key: "# of cores")
                    if let cores = gpuCores ?? altCores {
                        coreCount = cores
                    }
                }

                // Try to get GPU usage using powermetrics (this will require running a subprocess)
                // For now, we'll set usage to 0 as fallback
                usage = 0.0
                note += " • Usage: Not directly available"
            } else {
                // For external GPUs, we can't get usage easily either
                usage = 0.0
                note += " • External GPU"
            }

            let gpu = GPUStatus(
                name: name,
                usage: usage,
                memoryUsed: memoryUsed,
                memoryTotal: memoryTotal,
                coreCount: coreCount,
                note: note
            )

            gpus.append(gpu)
        }

        return gpus
    }
}