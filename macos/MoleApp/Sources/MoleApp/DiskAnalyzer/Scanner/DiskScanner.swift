import Foundation

/// Core disk scanning engine
final class DiskScanner {
    private let limiter: ScanLimiter
    private let fileManager = FileManager.default
    private let scanCache: ScanCache

    // Track scanned paths to avoid duplicate work
    private var scannedPaths: Set<String> = []
    private let scanLock = NSLock()

    init() {
        self.limiter = ScanLimiter()
        self.scanCache = ScanCache()
    }

    // MARK: - Main Scanning Methods

    /// Scan a path and return Top30 entries + Top20 large files
    func scan(path: String) async throws -> ScanResult {
        return try await scanPath(path: path, maxEntries: ScanConfig.maxEntries, maxLargeFiles: ScanConfig.maxLargeFiles)
    }

    /// Scan all entries (no Top-N limit, for JSON mode)
    func scanAllEntries(path: String) async throws -> ScanResult {
        return try await scanPath(path: path, maxEntries: 0, maxLargeFiles: 0)
    }

    /// Overview scan (root level only)
    func scanOverview() async throws -> AnalyzeOutput {
        let rootPath = "/"
        let result = try await scanPath(path: rootPath, maxEntries: ScanConfig.maxEntries, maxLargeFiles: ScanConfig.maxLargeFiles)

        return AnalyzeOutput(
            path: rootPath,
            overview: true,
            entries: result.entries.map { entry in
                AnalyzeEntry(name: entry.name, path: entry.path, size: entry.size, isDir: entry.isDir)
            },
            largeFiles: result.largeFiles.map { file in
                AnalyzeFile(name: file.name, path: file.path, size: file.size)
            },
            totalSize: result.totalSize,
            totalFiles: result.totalFiles
        )
    }

    /// JSON mode scan
    func scanJSON(path: String, isOverview: Bool) async throws -> AnalyzeOutput {
        let scanResult: ScanResult
        if isOverview {
            let overviewResult = try await scanOverview()
            scanResult = ScanResult(
                entries: overviewResult.entries.map { entry in
                    DirEntry(name: entry.name, path: entry.path, size: entry.size, isDir: entry.isDir, lastAccess: nil)
                },
                largeFiles: overviewResult.largeFiles?.map { file in
                    FileEntry(name: file.name, path: file.path, size: file.size, lastAccess: nil)
                } ?? [],
                totalSize: overviewResult.totalSize,
                totalFiles: overviewResult.totalFiles ?? 0
            )
        } else {
            scanResult = try await scanAllEntries(path: path)
        }

        return AnalyzeOutput(
            path: path,
            overview: isOverview,
            entries: scanResult.entries.map { entry in
                AnalyzeEntry(name: entry.name, path: entry.path, size: entry.size, isDir: entry.isDir)
            },
            largeFiles: scanResult.largeFiles.map { file in
                AnalyzeFile(name: file.name, path: file.path, size: file.size)
            },
            totalSize: scanResult.totalSize,
            totalFiles: scanResult.totalFiles
        )
    }

    // MARK: - Core Scanning Logic

    private func scanPath(path: String, maxEntries: Int, maxLargeFiles: Int) async throws -> ScanResult {
        // Check cache first
        if let cachedEntry = scanCache.get(path: path) {
            if cachedEntry.needsRefresh {
                // Cache is stale but within grace window - return cached data and refresh in background
                Task {
                    _ = try? await performScan(path: path, maxEntries: maxEntries, maxLargeFiles: maxLargeFiles, useCache: false)
                }
                return ScanResult(
                    entries: cachedEntry.entries,
                    largeFiles: cachedEntry.largeFiles,
                    totalSize: cachedEntry.totalSize,
                    totalFiles: cachedEntry.totalFiles
                )
            } else {
                // Cache is valid - use it
                return ScanResult(
                    entries: cachedEntry.entries,
                    largeFiles: cachedEntry.largeFiles,
                    totalSize: cachedEntry.totalSize,
                    totalFiles: cachedEntry.totalFiles
                )
            }
        }

        // No cache available - perform scan
        return try await performScan(path: path, maxEntries: maxEntries, maxLargeFiles: maxLargeFiles, useCache: true)
    }

    private func performScan(path: String, maxEntries: Int, maxLargeFiles: Int, useCache: Bool) async throws -> ScanResult {
        let contents = try fileManager.contentsOfDirectory(atPath: path)
        let collectAll = maxEntries <= 0

        var entries: [DirEntry] = []
        var largeFiles: [FileEntry] = []
        var totalSize: Int64 = 0
        var totalFiles: Int64 = 0

        // Use TaskGroup for concurrent scanning
        try await withThrowingTaskGroup(of: ScanItem?.self) { group in
            for item in contents {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false

                guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else {
                    continue
                }

                // MED-1 fix: Check for symbolic link to prevent infinite loops
                var isSymlink: ObjCBool = false
                if fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    // Use lstat to check for symbolic links (doesn't follow symlinks)
                    var stat = stat()
                    if lstat(fullPath, &stat) == 0 {
                        let isLink = (stat.st_mode & S_IFMT) == S_IFLNK
                        isSymlink = ObjCBool(isLink)
                    }
                }

                // If it's a symlink, only count the symlink itself, don't recurse
                if isSymlink.boolValue {
                    let symlinkSize = self.getActualFileSize(path: fullPath)
                    if symlinkSize > 0 {
                        totalSize += symlinkSize
                        totalFiles += 1
                        entries.append(DirEntry(name: item, path: fullPath, size: symlinkSize, isDir: false, lastAccess: nil))
                    }
                    continue
                }

                if isDir.boolValue {
                    // Directory handling
                    if shouldSkip(name: item, path: fullPath) {
                        continue
                    }

                    let isFolded = DirectoryRules.foldDirs.contains(item)

                    group.addTask { [weak self] in
                        guard let self = self else { return nil }

                        // Check if already scanned
                        if self.isPathScanned(fullPath) {
                            return nil
                        }
                        self.markPathScanned(fullPath)

                        await self.limiter.entrySem.wait()

                        if isFolded {
                            let size = await self.runDuSize(path: fullPath)
                            // MED-2 fix: Synchronous semaphore release
                            await self.limiter.entrySem.signal()
                            return .dir(size, item, fullPath, true)
                        } else {
                            await self.limiter.dirSem.wait()
                            let size = await self.runDuSize(path: fullPath)
                            // MED-2 fix: Synchronous semaphore release
                            await self.limiter.entrySem.signal()
                            await self.limiter.dirSem.signal()
                            return .dir(size, item, fullPath, false)
                        }
                    }
                } else {
                    // File handling - use actual disk size instead of logical size
                    let actualSize = self.getActualFileSize(path: fullPath)

                    if actualSize > 0 {
                        group.addTask {
                            // Large files: get last access time
                            if actualSize > ScanConfig.largeFileWarmupMinSize {
                                let lastAccess = await self.getMDLSLastAccess(path: fullPath)
                                return .file(actualSize, item, fullPath, lastAccess)
                            }
                            return .file(actualSize, item, fullPath, nil)
                        }
                    }
                }
            }

            // Collect results
            for try await item in group {
                switch item {
                case .dir(let size, let name, let fullPath, _):
                    totalSize += size
                    entries.append(DirEntry(name: name, path: fullPath, size: size, isDir: true, lastAccess: nil))

                case .file(let size, let name, let fullPath, let lastAccess):
                    totalSize += size
                    totalFiles += 1

                    let fileEntry = FileEntry(name: name, path: fullPath, size: size, lastAccess: lastAccess)

                    // Add to large files if significant
                    if size > ScanConfig.largeFileWarmupMinSize {
                        largeFiles.append(fileEntry)
                    }

                    // Also add to entries for Top-N
                    entries.append(DirEntry(name: name, path: fullPath, size: size, isDir: false, lastAccess: lastAccess))

                case nil:
                    break
                }
            }
        }

        // Apply Top-N sorting
        let sortedEntries = entries.sorted { $0.size > $1.size }
        let topEntries = collectAll ? sortedEntries : Array(sortedEntries.prefix(maxEntries))

        let sortedLargeFiles = largeFiles.sorted { $0.size > $1.size }
        let topLargeFiles = collectAll ? sortedLargeFiles : Array(sortedLargeFiles.prefix(maxLargeFiles))

        let result = ScanResult(entries: topEntries, largeFiles: topLargeFiles, totalSize: totalSize, totalFiles: totalFiles)

        // Save to cache if requested
        if useCache {
            let modTime = getModTime(for: path)
            let cacheEntry = CacheEntry(
                entries: topEntries,
                largeFiles: topLargeFiles,
                totalSize: totalSize,
                totalFiles: totalFiles,
                modTime: modTime ?? Date(),
                scanTime: Date(),
                needsRefresh: false
            )
            scanCache.set(path: path, entry: cacheEntry)
        }

        return result
    }

    // MARK: - Helper Methods

    private func shouldSkip(name: String, path: String) -> Bool {
        // Root directory special handling
        if path == "/" {
            if let skip = DirectoryRules.skipSystemDirs[name], skip {
                return true
            }
        }

        // Global skip
        if DirectoryRules.defaultSkipDirs.contains(name) {
            return true
        }

        // Hidden directories (except .Trash at root)
        if name.hasPrefix(".") && name != ".Trash" {
            return path != "/"
        }

        return false
    }

    private func isPathScanned(_ path: String) -> Bool {
        scanLock.lock()
        defer { scanLock.unlock() }
        return scannedPaths.contains(path)
    }

    private func markPathScanned(_ path: String) {
        scanLock.lock()
        defer { scanLock.unlock() }
        scannedPaths.insert(path)
    }

    private func getModTime(for path: String) -> Date? {
        try? fileManager.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    // MARK: - Process Integration

    /// Call du -sk to get directory size
    func runDuSize(path: String) async -> Int64 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
            process.arguments = ["-sk", path]

            let pipe = Pipe()
            process.standardOutput = pipe

            // CRIT-2 fix: Use atomic flag to prevent double-resume
            var hasResumed = false
            let resumeOnce: (Int64) -> Void = { value in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: value)
            }

            // Timeout handling
            let timeoutTask = DispatchWorkItem {
                if process.isRunning { process.terminate() }
                resumeOnce(0)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + ScanConfig.duTimeout, execute: timeoutTask)

            process.terminationHandler = { _ in
                timeoutTask.cancel()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                // Parse "12345\t/path"
                if let firstLine = output.components(separatedBy: .newlines).first,
                   let kbStr = firstLine.components(separatedBy: .whitespaces).first,
                   let kb = Int64(kbStr) {
                    resumeOnce(kb * 1024)
                } else {
                    resumeOnce(0)
                }
            }

            do {
                try process.run()
            } catch {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: 0)
            }
        }
    }

    /// Call mdls to get file last access time
    func getMDLSLastAccess(path: String) async -> Date? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
            process.arguments = ["-name", "kMDItemLastUsedDate", path]

            let pipe = Pipe()
            process.standardOutput = pipe

            // CRIT-2 fix: Use atomic flag to prevent double-resume
            var hasResumed = false
            let resumeOnce: (Date?) -> Void = { value in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: value ?? nil)
            }
            let resumeErrorOnce: (Error) -> Void = { error in
                guard !hasResumed else { return }
                hasResumed = true
                // For non-throwing continuation, return nil on error
                continuation.resume(returning: nil)
            }

            // Timeout handling
            let timeoutTask = DispatchWorkItem {
                if process.isRunning { process.terminate() }
                resumeOnce(nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + ScanConfig.mdlsTimeout, execute: timeoutTask)

            process.terminationHandler = { _ in
                timeoutTask.cancel()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                // Parse "kMDItemLastUsedDate = 2024-01-15 10:30:00 +0000"
                if let range = output.range(of: "= ") {
                    let dateStr = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
                    resumeOnce(formatter.date(from: dateStr))
                } else {
                    resumeOnce(nil)
                }
            }

            do {
                try process.run()
            } catch {
                resumeErrorOnce(error)
            }
        }
    }

    /// Use mdfind to find large files (>100MB) for Spotlight预热
    func findLargeFilesWithSpotlight(path: String) async -> [FileEntry] {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            process.arguments = [
                "-onlyin", path,
                "kMDItemFSSize > \(ScanConfig.spotlightMinFileSize)"
            ]

            let pipe = Pipe()
            process.standardOutput = pipe

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                var entries: [FileEntry] = []

                for line in output.components(separatedBy: .newlines) {
                    guard !line.isEmpty else { continue }
                    let url = URL(fileURLWithPath: line)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: line),
                       let size = attrs[.size] as? Int64 {
                        entries.append(FileEntry(name: url.lastPathComponent, path: line, size: size))
                    }
                }
                continuation.resume(returning: entries)
            }

            try? process.run()
        }
    }

    /// Get actual disk usage using stat.Blocks * 512
    func getActualFileSize(path: String) -> Int64 {
        var stat = stat()
        guard lstat(path, &stat) == 0 else { return 0 }
        return Int64(stat.st_blocks) * 512
    }
}