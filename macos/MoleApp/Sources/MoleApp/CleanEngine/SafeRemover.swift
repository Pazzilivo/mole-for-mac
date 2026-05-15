import Foundation

/// Thread-safe file removal with trash-first strategy
actor SafeRemover {
    // MARK: - Properties
    private let configuration: CleanEngineConfiguration
    private let fileManager = FileManager.default
    private let pathValidator: PathValidator
    private let whitelistManager: WhitelistManager
    private let protectionManager: ProtectionManager

    // MARK: - Initialization
    init(
        configuration: CleanEngineConfiguration,
        pathValidator: PathValidator,
        whitelistManager: WhitelistManager,
        protectionManager: ProtectionManager
    ) {
        self.configuration = configuration
        self.pathValidator = pathValidator
        self.whitelistManager = whitelistManager
        self.protectionManager = protectionManager
    }

    // MARK: - Public Removal Methods
    func remove(_ target: CleanItem) async -> CleanResult {
        let startTime = Date()

        // Check if this is a dry run
        if configuration.dryRun {
            return CleanResult(
                target: target,
                status: .success,
                actualSizeRemoved: 0,
                errorMessage: nil,
                duration: Date().timeIntervalSince(startTime)
            )
        }

        // Validate path before removal
        let validation = await pathValidator.validate(target.path)
        guard validation.canProceed else {
            return CleanResult(
                target: target,
                status: .failed,
                actualSizeRemoved: 0,
                errorMessage: validation.errors.map { $0.localizedDescription }.joined(separator: ", "),
                duration: Date().timeIntervalSince(startTime)
            )
        }

        // Check whitelist
        if configuration.respectWhitelist {
            let isWhitelisted = await whitelistManager.isWhitelisted(target.path)
            if isWhitelisted {
                return CleanResult(
                    target: target,
                    status: .skipped,
                    actualSizeRemoved: 0,
                    errorMessage: "Path is whitelisted",
                    duration: Date().timeIntervalSince(startTime)
                )
            }
        }

        // Check protections
        if configuration.respectProtections {
            let isProtected = await protectionManager.shouldProtectPath(target.path, mode: configuration.mode)
            if isProtected {
                return CleanResult(
                    target: target,
                    status: .skipped,
                    actualSizeRemoved: 0,
                    errorMessage: "Path is protected",
                    duration: Date().timeIntervalSince(startTime)
                )
            }
        }

        // Perform removal based on configuration
        let result: CleanResult
        if configuration.useTrash && configuration.mode != .aggressive {
            result = await moveToTrash(target)
        } else {
            result = await permanentRemove(target)
        }

        return result
    }

    func batchRemove(_ targets: [CleanItem]) async -> [CleanResult] {
        var results: [CleanResult] = []

        // Process in batches based on maxConcurrentOperations
        let batchSize = configuration.maxConcurrentOperations
        var batch: [CleanItem] = []

        for target in targets {
            batch.append(target)

            if batch.count >= batchSize {
                let batchResults = await withTaskGroup(of: CleanResult.self) { group in
                    var batchResults: [CleanResult] = []

                    for batchTarget in batch {
                        group.addTask {
                            await self.remove(batchTarget)
                        }
                    }

                    for await result in group {
                        batchResults.append(result)
                    }

                    return batchResults
                }

                results.append(contentsOf: batchResults)
                batch.removeAll()
            }
        }

        // Process remaining items in the last batch
        if !batch.isEmpty {
            let batchResults = await withTaskGroup(of: CleanResult.self) { group in
                var batchResults: [CleanResult] = []

                for batchTarget in batch {
                    group.addTask {
                        await self.remove(batchTarget)
                    }
                }

                for await result in group {
                    batchResults.append(result)
                }

                return batchResults
            }

            results.append(contentsOf: batchResults)
        }

        return results
    }

    // MARK: - Private Removal Methods
    private func moveToTrash(_ target: CleanItem) async -> CleanResult {
        let startTime = Date()
        let url = URL(fileURLWithPath: target.path)

        do {
            try fileManager.trashItem(at: url, resultingItemURL: nil)

            return CleanResult(
                target: target,
                status: .success,
                actualSizeRemoved: target.size,
                errorMessage: nil,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch {
            // If trash fails, fall back to permanent removal
            return await permanentRemove(target)
        }
    }

    private func permanentRemove(_ target: CleanItem) async -> CleanResult {
        let startTime = Date()
        let url = URL(fileURLWithPath: target.path)

        do {
            // Check if path exists
            guard fileManager.fileExists(atPath: target.path) else {
                return CleanResult(
                    target: target,
                    status: .skipped,
                    actualSizeRemoved: 0,
                    errorMessage: "File does not exist",
                    duration: Date().timeIntervalSince(startTime)
                )
            }

            // Remove based on type
            var actualSizeRemoved: Int64 = 0

            if target.type == .directory {
                actualSizeRemoved = calculateDirectorySize(target.path)
            } else {
                actualSizeRemoved = target.size
            }

            try fileManager.removeItem(at: url)

            return CleanResult(
                target: target,
                status: .success,
                actualSizeRemoved: actualSizeRemoved,
                errorMessage: nil,
                duration: Date().timeIntervalSince(startTime)
            )
        } catch let error as NSError {
            let errorMessage: String
            let status: CleanResult.CleanStatus

            switch error.code {
            case NSFileReadNoPermissionError:
                errorMessage = "Permission denied"
                status = .failed
            case NSFileNoSuchFileError:
                errorMessage = "File not found"
                status = .skipped
            case NSFileWriteFileExistsError:
                errorMessage = "File exists (cannot overwrite)"
                status = .failed
            default:
                errorMessage = error.localizedDescription
                status = .failed
            }

            return CleanResult(
                target: target,
                status: status,
                actualSizeRemoved: 0,
                errorMessage: errorMessage,
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }

    // MARK: - Size Calculation
    private func calculateDirectorySize(_ path: String) -> Int64 {
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path),
                                                      includingPropertiesForKeys: [.fileSizeKey],
                                                      options: [.skipsHiddenFiles]) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                continue
            }
        }

        return totalSize
    }

    // MARK: - Validation Helpers
    func canRemove(_ target: CleanItem) async -> Bool {
        // Check if this is a dry run (always safe)
        if configuration.dryRun {
            return true
        }

        // Validate path
        let validation = await pathValidator.validate(target.path)
        guard validation.canProceed else {
            return false
        }

        // Check whitelist
        if configuration.respectWhitelist {
            let isWhitelisted = await whitelistManager.isWhitelisted(target.path)
            if isWhitelisted {
                return false
            }
        }

        // Check protections
        if configuration.respectProtections {
            let isProtected = await protectionManager.shouldProtectPath(target.path, mode: configuration.mode)
            if isProtected {
                return false
            }
        }

        return true
    }

    func getRemovalPreview(_ targets: [CleanItem]) async -> (totalSize: Int64, protectedCount: Int, removableCount: Int) {
        var totalSize: Int64 = 0
        var protectedCount = 0
        var removableCount = 0

        for target in targets {
            if await canRemove(target) {
                totalSize += target.size
                removableCount += 1
            } else {
                protectedCount += 1
            }
        }

        return (totalSize, protectedCount, removableCount)
    }

    // MARK: - Specialized Removal Methods
    func removeWithRetry(_ target: CleanItem, maxRetries: Int = 3) async -> CleanResult {
        var lastResult = await remove(target)

        guard lastResult.status == .failed else {
            return lastResult
        }

        // Retry logic for permission errors
        if let errorMessage = lastResult.errorMessage,
           errorMessage.contains("Permission denied") {

            for attempt in 1...maxRetries {
                // Wait before retry (exponential backoff)
                try? await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))

                let retryResult = await remove(target)
                if retryResult.status == .success {
                    return retryResult
                }

                lastResult = retryResult
            }
        }

        return lastResult
    }

    func removeWithVerification(_ target: CleanItem) async -> CleanResult {
        let result = await remove(target)

        // Verify removal was successful
        if result.status == .success {
            if fileManager.fileExists(atPath: target.path) {
                // File still exists despite success status
                return CleanResult(
                    target: target,
                    status: .partial,
                    actualSizeRemoved: result.actualSizeRemoved,
                    errorMessage: "File may still exist after removal",
                    duration: result.duration
                )
            }
        }

        return result
    }

    // MARK: - Cleanup Statistics
    func estimateRemovalTime(_ targets: [CleanItem]) -> TimeInterval {
        let totalSize = targets.reduce(Int64(0)) { $0 + $1.size }
        let fileCount = targets.count

        // Rough estimation: 100MB per second for small files, 50MB/s for large operations
        let sizeBasedTime = Double(totalSize) / (100_000_000) // Assume 100MB/s
        let fileBasedTime = Double(fileCount) * 0.01 // Assume 10ms per file

        return max(sizeBasedTime, fileBasedTime)
    }

    func getDiskSpaceToBeReclaimed(_ targets: [CleanItem]) async -> Int64 {
        var totalSpace: Int64 = 0

        for target in targets {
            if await canRemove(target) {
                totalSpace += target.size
            }
        }

        return totalSpace
    }
}

// MARK: - Removal Strategies
enum RemovalStrategy {
    case trashFirst
    case permanent
    case hybrid

    var description: String {
        switch self {
        case .trashFirst: return "Move to Trash first"
        case .permanent: return "Permanent removal"
        case .hybrid: return "Trash with permanent fallback"
        }
    }
}

// MARK: - Removal Progress
struct RemovalProgress {
    let totalTargets: Int
    let processedTargets: Int
    let succeededTargets: Int
    let failedTargets: Int
    let skippedTargets: Int
    let totalSizeRemoved: Int64
    let currentTarget: CleanItem?

    var progress: Double {
        guard totalTargets > 0 else { return 0.0 }
        return Double(processedTargets) / Double(totalTargets)
    }

    var percentage: Int {
        return Int(progress * 100)
    }

    var formattedProgress: String {
        return "\(processedTargets)/\(totalTargets) (\(percentage)%)"
    }
}

// MARK: - Removal Error
enum RemovalError: Error, LocalizedError {
    case permissionDenied(String)
    case fileInUse(String)
    case systemProtected(String)
    case invalidPath(String)
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .fileInUse(let path):
            return "File in use: \(path)"
        case .systemProtected(let path):
            return "System protected: \(path)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}