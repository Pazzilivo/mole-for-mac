import Foundation

/// Main CleanEngine orchestration with validation-removal workflow
actor CleanEngine {
    // MARK: - Components
    private let pathValidator: PathValidator
    private let whitelistManager: WhitelistManager
    private let protectionManager: ProtectionManager
    private let safeRemover: SafeRemover

    // MARK: - Properties
    private(set) var configuration: CleanEngineConfiguration
    private(set) var statistics: CleanStatistics

    // MARK: - Initialization
    init(configuration: CleanEngineConfiguration = .default) {
        self.configuration = configuration

        // Initialize components
        self.pathValidator = PathValidator()
        self.whitelistManager = WhitelistManager()
        self.protectionManager = ProtectionManager()
        self.safeRemover = SafeRemover(
            configuration: configuration,
            pathValidator: pathValidator,
            whitelistManager: whitelistManager,
            protectionManager: protectionManager
        )

        self.statistics = CleanStatistics()
    }

    // MARK: - Main Public Interface
    func scan(_ paths: [String]) async -> [CleanItem] {
        var targets: [CleanItem] = []

        for path in paths {
            let pathTargets = await scan(path)
            targets.append(contentsOf: pathTargets)
        }

        return targets
    }

    func clean(_ targets: [CleanItem]) async -> [CleanResult] {
        statistics.startTime = Date()
        statistics.totalScanned = targets.count

        // Filter targets based on validation and protection
        let removableTargets = await filterRemovableTargets(targets)
        statistics.totalSkipped = targets.count - removableTargets.count

        // Perform cleaning
        let results = await safeRemover.batchRemove(removableTargets)

        // Update statistics
        for result in results {
            switch result.status {
            case .success:
                statistics.recordCleaned(size: result.actualSizeRemoved)
            case .failed:
                statistics.recordFailed()
            case .skipped:
                statistics.recordSkipped()
            case .partial:
                statistics.recordCleaned(size: result.actualSizeRemoved)
                statistics.recordFailed()
            }
        }

        statistics.complete()
        return results
    }

    func analyze(_ path: String) async -> [CleanItem] {
        return await scan(path)
    }

    // MARK: - Configuration Management
    func updateConfiguration(_ newConfiguration: CleanEngineConfiguration) {
        self.configuration = newConfiguration
    }

    func updateMode(_ mode: CleanMode) {
        configuration = CleanEngineConfiguration(
            mode: mode,
            useTrash: configuration.useTrash,
            preserveUserSettings: configuration.preserveUserSettings,
            respectWhitelist: configuration.respectWhitelist,
            respectProtections: configuration.respectProtections,
            maxConcurrentOperations: configuration.maxConcurrentOperations,
            dryRun: configuration.dryRun
        )
    }

    // MARK: - Statistics & Monitoring
    func getStatistics() -> CleanStatistics {
        return statistics
    }

    func resetStatistics() {
        statistics = CleanStatistics()
    }

    // MARK: - Whitelist Management
    func addWhitelistPattern(_ pattern: String) async {
        await whitelistManager.addPattern(pattern)
    }

    func removeWhitelistPattern(_ pattern: String) async {
        await whitelistManager.removePattern(pattern)
    }

    func getWhitelistPatterns() async -> [String] {
        return await whitelistManager.getAllPatterns()
    }

    func loadWhitelist(from url: URL) async throws {
        try await whitelistManager.loadPatterns(from: url)
    }

    func exportWhitelist(to url: URL) async throws {
        try await whitelistManager.exportPatterns(to: url)
    }

    // MARK: - Protection Management
    func getProtectionLevel(for path: String) async -> RiskLevel {
        return await protectionManager.getProtectionLevel(for: path)
    }

    func isProtected(_ path: String) async -> Bool {
        return await protectionManager.shouldProtectPath(path, mode: configuration.mode)
    }

    // MARK: - Validation
    func validate(_ path: String) async -> ValidationResult {
        return await pathValidator.validate(path)
    }

    func inspect(_ path: String) async -> PathInspectionResult? {
        return await pathValidator.inspect(path)
    }

    // MARK: - Preview & Planning
    func previewCleaning(_ targets: [CleanItem]) async -> CleaningPreview {
        let preview = await safeRemover.getRemovalPreview(targets)
        let estimatedTime = await safeRemover.estimateRemovalTime(targets)

        return CleaningPreview(
            totalTargets: targets.count,
            removableTargets: preview.removableCount,
            protectedTargets: preview.protectedCount,
            totalSize: preview.totalSize,
            estimatedTime: estimatedTime,
            mode: configuration.mode
        )
    }

    // MARK: - Private Methods
    private func scan(_ path: String) async -> [CleanItem] {
        var targets: [CleanItem] = []

        // Validate path first
        let validation = await pathValidator.validate(path)
        guard validation.canProceed else {
            return []
        }

        // Check if path exists
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }

        // Inspect the path
        guard let inspection = await pathValidator.inspect(path) else {
            return []
        }

        // Check protection and whitelist
        let isProtected = await protectionManager.shouldProtectPath(path, mode: configuration.mode)
        let isWhitelisted = configuration.respectWhitelist ? await whitelistManager.isWhitelisted(path) : false

        // Create target
        let target = CleanItem(
            path: path,
            size: inspection.size,
            type: inspection.type,
            category: inspection.suggestedCategory,
            riskLevel: inspection.estimatedRisk,
            lastAccessed: inspection.lastAccessed,
            isProtected: isProtected,
            isWhitelisted: isWhitelisted
        )

        targets.append(target)

        // If directory, scan contents
        if inspection.type == .directory {
            let contentsTargets = await scanDirectoryContents(path)
            targets.append(contentsOf: contentsTargets)
        }

        return targets
    }

    private func scanDirectoryContents(_ path: String) async -> [CleanItem] {
        var targets: [CleanItem] = []

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for item in contents {
                let itemTargets = await scan(item.path)
                targets.append(contentsOf: itemTargets)
            }
        } catch {
            // Skip directories we can't read
        }

        return targets
    }

    private func filterRemovableTargets(_ targets: [CleanItem]) async -> [CleanItem] {
        var removableTargets: [CleanItem] = []

        for target in targets {
            // Skip if protected
            if target.isProtected && configuration.respectProtections {
                continue
            }

            // Skip if whitelisted
            if target.isWhitelisted && configuration.respectWhitelist {
                continue
            }

            // Skip if validation fails
            let validation = await pathValidator.validate(target.path)
            if !validation.canProceed {
                continue
            }

            removableTargets.append(target)
        }

        return removableTargets
    }
}

// MARK: - Cleaning Preview
struct CleaningPreview: Sendable {
    let totalTargets: Int
    let removableTargets: Int
    let protectedTargets: Int
    let totalSize: Int64
    let estimatedTime: TimeInterval
    let mode: CleanMode

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var formattedTime: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: estimatedTime) ?? "Unknown"
    }

    var protectionRate: Double {
        guard totalTargets > 0 else { return 0.0 }
        return Double(protectedTargets) / Double(totalTargets)
    }

    var safetyScore: String {
        let score = 1.0 - protectionRate
        switch score {
        case 0.8...1.0: return "Very Safe"
        case 0.6..<0.8: return "Safe"
        case 0.4..<0.6: return "Moderate"
        case 0.2..<0.4: return "Caution"
        default: return "Risky"
        }
    }
}

// MARK: - Clean Engine Events
enum CleanEngineEvent: Sendable {
    case scanningStarted(path: String)
    case scanningProgress(current: Int, total: Int)
    case scanningCompleted(targetsFound: Int)

    case cleaningStarted(targetCount: Int)
    case cleaningProgress(result: CleanResult)
    case cleaningCompleted(results: [CleanResult])

    case errorOccurred(error: CleanEngineError)
    case warningGenerated(warning: ValidationWarning)

    var description: String {
        switch self {
        case .scanningStarted(let path):
            return "Scanning: \(path)"
        case .scanningProgress(let current, let total):
            return "Scanning progress: \(current)/\(total)"
        case .scanningCompleted(let targetsFound):
            return "Scanning completed: \(targetsFound) targets found"
        case .cleaningStarted(let targetCount):
            return "Cleaning started: \(targetCount) targets"
        case .cleaningProgress(let result):
            return "Cleaning: \(result.target.path) - \(result.status.rawValue)"
        case .cleaningCompleted(let results):
            return "Cleaning completed: \(results.count) results"
        case .errorOccurred(let error):
            return "Error: \(error.errorDescription ?? "Unknown error")"
        case .warningGenerated(let warning):
            return "Warning: \(warning.localizedDescription)"
        }
    }
}

// MARK: - Clean Engine Delegate
@MainActor
protocol CleanEngineDelegate: AnyObject {
    func cleanEngine(_ engine: CleanEngine, didReceiveEvent: CleanEngineEvent)
    func cleanEngine(_ engine: CleanEngine, didUpdateProgress: Double)
    func cleanEngine(_ engine: CleanEngine, didCompleteWith: CleanStatistics)
}

// MARK: - Clean Engine Observable (for SwiftUI)
@MainActor
class ObservableCleanEngine: ObservableObject {
    @Published var statistics: CleanStatistics = CleanStatistics()
    @Published var currentEvent: CleanEngineEvent?
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0.0
    @Published var errorMessage: String?

    private let engine: CleanEngine

    init(engine: CleanEngine = CleanEngine()) {
        self.engine = engine
    }

    func scan(_ paths: [String]) async -> [CleanItem] {
        isProcessing = true
        progress = 0.0
        currentEvent = .scanningStarted(path: paths.first ?? "")

        let targets = await engine.scan(paths)

        currentEvent = .scanningCompleted(targetsFound: targets.count)
        isProcessing = false
        progress = 1.0

        return targets
    }

    func clean(_ targets: [CleanItem]) async -> [CleanResult] {
        isProcessing = true
        progress = 0.0
        currentEvent = .cleaningStarted(targetCount: targets.count)

        let results = await engine.clean(targets)

        currentEvent = .cleaningCompleted(results: results)
        statistics = await engine.getStatistics()
        isProcessing = false
        progress = 1.0

        return results
    }

    func preview(_ targets: [CleanItem]) async -> CleaningPreview {
        return await engine.previewCleaning(targets)
    }

    func updateConfiguration(_ configuration: CleanEngineConfiguration) async {
        await engine.updateConfiguration(configuration)
    }

    func addWhitelistPattern(_ pattern: String) async {
        await engine.addWhitelistPattern(pattern)
    }

    func removeWhitelistPattern(_ pattern: String) async {
        await engine.removeWhitelistPattern(pattern)
    }
}