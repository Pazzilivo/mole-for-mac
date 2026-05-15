import Foundation

// MARK: - Clean Item
/// Represents a file or directory to be cleaned
struct CleanItem: Identifiable, Sendable {
    let id = UUID()
    let path: String
    let size: Int64
    let type: CleanType
    let category: CleanItemCategory
    let riskLevel: RiskLevel
    let lastAccessed: Date?
    let isProtected: Bool
    let isWhitelisted: Bool

    enum CleanType: String, Sendable {
        case file
        case directory
        case symlink
        case bundle
    }
}

// MARK: - Clean Result
/// Result of a cleaning operation
struct CleanResult: Sendable {
    let target: CleanItem
    let status: CleanStatus
    let actualSizeRemoved: Int64
    let errorMessage: String?
    let duration: TimeInterval

    enum CleanStatus: String, Sendable {
        case success
        case failed
        case skipped
        case partial
    }
}

// MARK: - Clean Category
/// Categories of cleanable items
enum CleanItemCategory: String, CaseIterable, Sendable {
    case systemCaches = "System Caches"
    case userCaches = "User Caches"
    case applicationCaches = "Application Caches"
    case logFiles = "Log Files"
    case temporaryFiles = "Temporary Files"
    case browserData = "Browser Data"
    case developmentTools = "Development Tools"
    case applicationSupport = "Application Support"
    case containers = "Containers"
    case leftovers = "Leftovers"
    case downloads = "Downloads"
    case trash = "Trash"
    case other = "Other"

    var icon: String {
        switch self {
        case .systemCaches: return "gearshape"
        case .userCaches: return "caches"
        case .applicationCaches: return "app"
        case .logFiles: return "doc.text"
        case .temporaryFiles: return "clock"
        case .browserData: return "safari"
        case .developmentTools: return "hammer"
        case .applicationSupport: return "folder"
        case .containers: return "box"
        case .leftovers: return "trash"
        case .downloads: return "arrow.down.circle"
        case .trash: return "trash"
        case .other: return "questionmark.circle"
        }
    }

    var description: String {
        switch self {
        case .systemCaches: return "System cache files"
        case .userCaches: return "User-level cache files"
        case .applicationCaches: return "Application-specific caches"
        case .logFiles: return "Application and system logs"
        case .temporaryFiles: return "Temporary files and folders"
        case .browserData: return "Browser caches and data"
        case .developmentTools: return "Development tool artifacts"
        case .applicationSupport: return "Application support data"
        case .containers: return "Sandboxed app containers"
        case .leftovers: return " remnants from uninstalled apps"
        case .downloads: return "Old downloads"
        case .trash: return "Trash contents"
        case .other: return "Other cleanable items"
        }
    }
}

// MARK: - Risk Level
/// Risk assessment for cleaning operations
enum RiskLevel: String, Comparable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var score: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "orange"
        case .high: return "red"
        }
    }

    var description: String {
        switch self {
        case .low: return "Safe to clean"
        case .medium: return "Review before cleaning"
        case .high: return "Critical - careful review required"
        }
    }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        return lhs.score < rhs.score
    }
}

// MARK: - Clean Mode
/// Different cleaning operation modes
enum CleanMode: String, Sendable {
    case dryRun = "Dry Run"
    case standard = "Standard"
    case aggressive = "Aggressive"
    case safe = "Safe"

    var description: String {
        switch self {
        case .dryRun: return "Preview without making changes"
        case .standard: return "Standard cleaning with safety checks"
        case .aggressive: return "Deep cleaning (may remove more data)"
        case .safe: return "Conservative cleaning (minimal risk)"
        }
    }

    var allowsSystemFiles: Bool {
        switch self {
        case .dryRun, .standard: return false
        case .aggressive: return true
        case .safe: return false
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .dryRun: return false
        case .standard, .aggressive, .safe: return true
        }
    }
}

// MARK: - Clean Engine Configuration
/// Configuration for the clean engine
struct CleanEngineConfiguration: Sendable {
    let mode: CleanMode
    let useTrash: Bool
    let preserveUserSettings: Bool
    let respectWhitelist: Bool
    let respectProtections: Bool
    let maxConcurrentOperations: Int
    let dryRun: Bool

    static let `default` = CleanEngineConfiguration(
        mode: .standard,
        useTrash: true,
        preserveUserSettings: true,
        respectWhitelist: true,
        respectProtections: true,
        maxConcurrentOperations: 4,
        dryRun: false
    )

    static let dryRun = CleanEngineConfiguration(
        mode: .dryRun,
        useTrash: false,
        preserveUserSettings: true,
        respectWhitelist: true,
        respectProtections: true,
        maxConcurrentOperations: 4,
        dryRun: true
    )

    static let aggressive = CleanEngineConfiguration(
        mode: .aggressive,
        useTrash: false,
        preserveUserSettings: false,
        respectWhitelist: true,
        respectProtections: true,
        maxConcurrentOperations: 8,
        dryRun: false
    )
}

// MARK: - Clean Engine Error
/// Errors that can occur during cleaning
enum CleanEngineError: Error, LocalizedError, Sendable {
    case validationFailed(String)
    case permissionDenied(String)
    case fileNotFound(String)
    case protectedPath(String)
    case whitelistedPath(String)
    case operationFailed(String)
    case configurationError(String)
    case concurrencyLimitReached
    case invalidPath(String)
    case systemProtection(String)

    var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .protectedPath(let path):
            return "Protected path: \(path)"
        case .whitelistedPath(let path):
            return "Whitelisted path: \(path)"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .concurrencyLimitReached:
            return "Concurrency limit reached"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .systemProtection(let message):
            return "System protection: \(message)"
        }
    }
}

// MARK: - Clean Statistics
/// Statistics for cleaning operations
struct CleanStatistics: Sendable {
    var totalScanned: Int = 0
    var totalCleaned: Int = 0
    var totalSkipped: Int = 0
    var totalFailed: Int = 0
    var totalSizeRemoved: Int64 = 0
    var duration: TimeInterval = 0.0
    var startTime: Date = Date()
    var endTime: Date?

    var successRate: Double {
        let total = totalScanned
        guard total > 0 else { return 0.0 }
        return Double(totalCleaned) / Double(total)
    }

    var formattedDuration: String {
        let duration = endTime.map { $0.timeIntervalSince(startTime) } ?? self.duration
        let durationInSeconds = TimeInterval(duration)
        return Duration.seconds(durationInSeconds).formatted(.time(pattern: .hourMinuteSecond))
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeRemoved, countStyle: .file)
    }

    mutating func recordScanned() {
        totalScanned += 1
    }

    mutating func recordCleaned(size: Int64) {
        totalCleaned += 1
        totalSizeRemoved += size
    }

    mutating func recordSkipped() {
        totalSkipped += 1
    }

    mutating func recordFailed() {
        totalFailed += 1
    }

    mutating func complete() {
        endTime = Date()
        duration = endTime?.timeIntervalSince(startTime) ?? 0.0
    }
}

// MARK: - Path Inspection Result
/// Result of inspecting a path for cleaning
struct PathInspectionResult: Sendable {
    let path: String
    let exists: Bool
    let isReadable: Bool
    let isWritable: Bool
    let size: Int64
    let type: CleanItem.CleanType
    let lastAccessed: Date?
    let lastModified: Date?
    let permissions: FilePermissions?
    let estimatedRisk: RiskLevel
    let suggestedCategory: CleanItemCategory

    struct FilePermissions: Sendable {
        let ownerRead: Bool
        let ownerWrite: Bool
        let ownerExecute: Bool
        let groupRead: Bool
        let groupWrite: Bool
        let groupExecute: Bool
        let otherRead: Bool
        let otherWrite: Bool
        let otherExecute: Bool
    }
}

// MARK: - Validation Result
/// Result of validating a path for cleaning
struct ValidationResult: Sendable {
    let isValid: Bool
    let errors: [ValidationError]
    let warnings: [ValidationWarning]

    var canProceed: Bool {
        return isValid && errors.isEmpty
    }

    var hasWarnings: Bool {
        return !warnings.isEmpty
    }
}

// MARK: - Validation Error
/// Specific validation errors
enum ValidationError: Error, Sendable {
    case emptyPath
    case relativePath(String)
    case pathTraversal(String)
    case systemPath(String)
    case protectedSystemPath(String)
    case invalidCharacters(String)
    case symbolicLinkTarget(String)

    var localizedDescription: String {
        switch self {
        case .emptyPath:
            return "Path cannot be empty"
        case .relativePath(let path):
            return "Path must be absolute: \(path)"
        case .pathTraversal(let path):
            return "Path traversal not allowed: \(path)"
        case .systemPath(let path):
            return "System path cannot be cleaned: \(path)"
        case .protectedSystemPath(let path):
            return "Protected system path: \(path)"
        case .invalidCharacters(let path):
            return "Path contains invalid characters: \(path)"
        case .symbolicLinkTarget(let target):
            return "Symbolic link target is protected: \(target)"
        }
    }
}

// MARK: - Validation Warning
/// Validation warnings that don't prevent cleaning
enum ValidationWarning: Sendable {
    case largeFile(size: Int64, path: String)
    case systemCritical(path: String)
    case recentlyAccessed(path: String, date: Date)
    case unusualPermissions(path: String)
    case networkVolume(path: String)

    var localizedDescription: String {
        switch self {
        case .largeFile(let size, let path):
            return "Large file (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))): \(path)"
        case .systemCritical(let path):
            return "System-critical path: \(path)"
        case .recentlyAccessed(let path, let date):
            return "Recently accessed (\(date.formatted())): \(path)"
        case .unusualPermissions(let path):
            return "Unusual permissions: \(path)"
        case .networkVolume(let path):
            return "Network volume: \(path)"
        }
    }
}