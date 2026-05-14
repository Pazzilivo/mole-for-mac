import Foundation

struct StatusSnapshot: Decodable {
    let collectedAt: Date?
    let host: String?
    let uptime: String?
    let hardware: HardwareInfo?
    let healthScore: Int?
    let healthScoreMsg: String?
    let cpu: CPUInfo?
    let memory: MemoryInfo?
    let disks: [DiskInfo]?
    let trashSize: UInt64?
    let topProcesses: [TopProcess]?

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case host
        case uptime
        case hardware
        case healthScore = "health_score"
        case healthScoreMsg = "health_score_msg"
        case cpu
        case memory
        case disks
        case trashSize = "trash_size"
        case topProcesses = "top_processes"
    }
}

struct HardwareInfo: Decodable {
    let model: String?
    let cpuModel: String?
    let totalRAM: String?
    let diskSize: String?
    let osVersion: String?

    enum CodingKeys: String, CodingKey {
        case model
        case cpuModel = "cpu_model"
        case totalRAM = "total_ram"
        case diskSize = "disk_size"
        case osVersion = "os_version"
    }
}

struct CPUInfo: Decodable {
    let usage: Double?
    let load1: Double?
    let load5: Double?
    let load15: Double?
    let logicalCPU: Int?

    enum CodingKeys: String, CodingKey {
        case usage
        case load1
        case load5
        case load15
        case logicalCPU = "logical_cpu"
    }
}

struct MemoryInfo: Decodable {
    let total: UInt64?
    let used: UInt64?
    let usedPercent: Double?
    let pressure: String?

    enum CodingKeys: String, CodingKey {
        case total
        case used
        case usedPercent = "used_percent"
        case pressure
    }
}

struct DiskInfo: Decodable, Identifiable {
    var id: String {
        mount ?? device ?? "disk-\(used ?? 0)-\(total ?? 0)"
    }

    let mount: String?
    let device: String?
    let used: UInt64?
    let total: UInt64?
    let usedPercent: Double?
    let external: Bool?

    enum CodingKeys: String, CodingKey {
        case mount
        case device
        case used
        case total
        case usedPercent = "used_percent"
        case external
    }
}

struct TopProcess: Decodable, Identifiable {
    var id: Int { pid ?? 0 }

    let pid: Int?
    let name: String?
    let command: String?
    let cpu: Double?
    let memory: Double?
}

struct AnalyzeOutput: Decodable {
    let path: String
    let overview: Bool
    let entries: [AnalyzeEntry]
    let largeFiles: [AnalyzeFile]?
    let totalSize: Int64
    let totalFiles: Int64?

    enum CodingKeys: String, CodingKey {
        case path
        case overview
        case entries
        case largeFiles = "large_files"
        case totalSize = "total_size"
        case totalFiles = "total_files"
    }
}

struct AnalyzeEntry: Decodable, Identifiable {
    var id: String { path }

    let name: String
    let path: String
    let size: Int64
    let isDir: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case size
        case isDir = "is_dir"
    }
}

struct AnalyzeFile: Decodable, Identifiable {
    var id: String { path }

    let name: String
    let path: String
    let size: Int64
}

struct AppEntry: Decodable, Identifiable {
    var id: String { path ?? uninstallName ?? name }

    let name: String
    let bundleID: String?
    let source: String?
    let uninstallName: String?
    let path: String?
    let size: String?

    enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundle_id"
        case source
        case uninstallName = "uninstall_name"
        case path
        case size
    }
}

struct OptimizePlan: Decodable {
    let memoryUsedGB: Double?
    let memoryTotalGB: Double?
    let diskUsedGB: Double?
    let diskTotalGB: Double?
    let diskUsedPercent: Double?
    let uptimeDays: Double?
    let optimizations: [OptimizeTask]

    enum CodingKeys: String, CodingKey {
        case memoryUsedGB = "memory_used_gb"
        case memoryTotalGB = "memory_total_gb"
        case diskUsedGB = "disk_used_gb"
        case diskTotalGB = "disk_total_gb"
        case diskUsedPercent = "disk_used_percent"
        case uptimeDays = "uptime_days"
        case optimizations
    }
}

struct OptimizeTask: Decodable, Identifiable {
    var id: String { action }

    let category: String
    let name: String
    let description: String
    let action: String
    let safe: Bool
}

struct ActivityLine: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isError: Bool
}

struct RuntimeCheck: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let isAvailable: Bool
}

struct OperationLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let command: String
    let action: String
    let path: String
    let detail: String
    let rawLine: String
    let isSession: Bool
}

struct DeletionLogEntry: Identifiable {
    let id = UUID()
    let timestamp: String
    let mode: String
    let sizeKB: String
    let status: String
    let path: String
    let rawLine: String
}

struct PlannedCommand: Identifiable {
    let id = UUID()
    let command: String
    let purpose: String
}

struct PlannedScreen: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let commands: [PlannedCommand]
    let safetyNotes: [String]
    let availableNow: [String]
}

enum LoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

enum ByteFormat {
    static func string(_ bytes: UInt64?) -> String {
        guard let bytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
