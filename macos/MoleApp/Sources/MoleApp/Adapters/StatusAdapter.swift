import Foundation

enum StatusAdapter {
    static func convert(_ metrics: SystemMetrics) -> StatusSnapshot {
        StatusSnapshot(
            collectedAt: metrics.collectedAt,
            host: metrics.host,
            uptime: metrics.uptime,
            hardware: convertHardware(metrics.hardware),
            healthScore: metrics.healthScore,
            healthScoreMsg: metrics.healthScoreMsg,
            cpu: convertCPU(metrics.cpu),
            memory: convertMemory(metrics.memory),
            disks: metrics.disks.map(convertDisk),
            trashSize: metrics.trashSize,
            topProcesses: metrics.topProcesses.map(convertProcess)
        )
    }

    private static func convertHardware(_ hw: HardwareStatus) -> HardwareInfo {
        HardwareInfo(
            model: hw.model,
            cpuModel: hw.cpuModel,
            totalRAM: hw.totalRAM,
            diskSize: hw.diskSize,
            osVersion: hw.osVersion
        )
    }

    private static func convertCPU(_ cpu: CPUStatus) -> CPUInfo {
        CPUInfo(
            usage: cpu.usage,
            load1: cpu.load1,
            load5: cpu.load5,
            load15: cpu.load15,
            logicalCPU: cpu.logicalCPU
        )
    }

    private static func convertMemory(_ mem: MemoryStatus) -> MemoryInfo {
        MemoryInfo(
            total: mem.total,
            used: mem.used,
            usedPercent: mem.usedPercent,
            pressure: mem.pressure
        )
    }

    private static func convertDisk(_ disk: DiskStatus) -> DiskInfo {
        DiskInfo(
            mount: disk.mount,
            device: disk.device,
            used: disk.used,
            total: disk.total,
            usedPercent: disk.usedPercent,
            external: disk.external
        )
    }

    private static func convertProcess(_ proc: ProcessEntry) -> TopProcess {
        TopProcess(
            pid: proc.pid,
            name: proc.name,
            command: proc.command,
            cpu: proc.cpu,
            memory: proc.memory
        )
    }
}
