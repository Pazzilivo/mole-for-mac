import Foundation

/// Cache entry that includes both size and timestamp
/// Fixed MED-3: Now includes per-entry timestamps
private struct OverviewCacheEntry: Codable {
    let size: Int64
    let timestamp: Date
}

/// Cache for disk overview scan results
/// Fixed CRIT-1: Deadlock bug resolved
/// Fixed MED-3: Now has per-entry timestamps
public class OverviewCache {
    private let cacheDirectory: URL
    private let cacheFile: URL
    private let cacheLock = NSLock()
    private var memoryCache: [String: OverviewCacheEntry] = [:]  // Fixed MED-3: Now stores OverviewCacheEntry instead of just Int64
    private let cacheValidityInterval: TimeInterval = 3600 // 1 hour

    public init(cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!) {
        self.cacheDirectory = cacheDirectory.appendingPathComponent("DiskAnalyzer")
        self.cacheFile = self.cacheDirectory.appendingPathComponent("overview.cache")
        self.loadFromDisk()
    }

    /// Fixed CRIT-1: No longer deadlocks - copies data within lock, writes to disk outside of lock
    /// Fixed MED-3: Now stores entries with per-entry timestamps
    public func set(path: String, size: Int64) {
        cacheLock.lock()
        let entry = OverviewCacheEntry(size: size, timestamp: Date())
        memoryCache[path] = entry
        let cacheToSave = memoryCache  // Copy data while holding lock
        cacheLock.unlock()

        // Write to disk outside of lock
        saveCacheToDisk(cacheToSave)
    }

    public func get(path: String) -> Int64? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return memoryCache[path]?.size  // Fixed MED-3: Extract size from OverviewCacheEntry
    }

    public func getAll() -> [String: Int64] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return memoryCache.mapValues { $0.size }  // Fixed MED-3: Extract sizes from OverviewCacheEntry
    }

    public func clear() {
        cacheLock.lock()
        memoryCache.removeAll()
        let emptyCache: [String: OverviewCacheEntry] = [:]  // Fixed MED-3: Clear with correct type
        cacheLock.unlock()

        // Write to disk outside of lock
        saveCacheToDisk(emptyCache)
    }

    /// Fixed MED-3: This method now checks per-entry timestamps instead of file mtime
    public func isValid(path: String) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        // Check if entry exists and is still valid based on its timestamp
        guard let entry = memoryCache[path] else {
            return false
        }

        // Check per-entry timestamp instead of file modification time
        let age = Date().timeIntervalSince(entry.timestamp)
        return age < cacheValidityInterval
    }

    // Fixed CRIT-1: This method no longer acquires the lock - caller is responsible for thread safety
    // Fixed MED-3: Now handles OverviewCacheEntry objects with timestamps
    private func saveCacheToDisk(_ cacheToSave: [String: OverviewCacheEntry]) {
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Save to disk
        if let data = try? JSONEncoder().encode(cacheToSave) {
            try? data.write(to: cacheFile)
        }
    }

    private func loadFromDisk() {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let data = try? Data(contentsOf: cacheFile),
              let decoded = try? JSONDecoder().decode([String: OverviewCacheEntry].self, from: data) else {  // Fixed MED-3: Decode OverviewCacheEntry objects
            return
        }

        memoryCache = decoded
    }
}