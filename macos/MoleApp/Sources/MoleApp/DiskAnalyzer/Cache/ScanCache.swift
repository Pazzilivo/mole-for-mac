import Foundation

// MARK: - Memory cache wrapper (NSCache requires NSObject subclass values)
final class MemoryCacheEntry: NSObject {
    let result: CacheEntry
    init(result: CacheEntry) { self.result = result }
}

// MARK: - ScanCache
/// Scan result cache with TTL and modTime-based invalidation
/// Fixed CRIT-3: Now uses stable, deterministic keys instead of unstable hash-based keys
final class ScanCache {
    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let ttl: TimeInterval = 7 * 24 * 3600  // 7 days
    private let graceWindow: TimeInterval = 30 * 60  // 30 minutes

    private let memoryCache = NSCache<NSString, MemoryCacheEntry>()

    init() {
        // Create cache directory in ~/Library/Caches/Mole/scan_cache/
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = cachesURL.appendingPathComponent("Mole/scan_cache")

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 10 * 1024 * 1024  // 10MB
    }

    /// Fixed CRIT-3: This method now generates stable, deterministic keys using percent-encoded paths
    private func cacheKey(for path: String) -> String {
        // Use percent-encoded path as a stable, deterministic key instead of unstable hashValue
        return path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
    }

    private func cacheFileURL(for path: String) -> URL {
        return cacheDirectory.appendingPathComponent(cacheKey(for: path) + ".json")
    }

    private func getModTime(for path: String) -> Date? {
        try? fileManager.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    func get(path: String) -> CacheEntry? {
        let key = path as NSString

        // Check memory cache first
        if let cached = memoryCache.object(forKey: key) {
            let now = Date()
            let cacheAge = now.timeIntervalSince(cached.result.scanTime)
            let isExpired = cacheAge > ttl
            let currentModTime = getModTime(for: path)
            let hasModTimeChanged = currentModTime != nil && currentModTime! > cached.result.modTime

            if !isExpired && !hasModTimeChanged {
                return cached.result
            }
            // Fall through to disk if expired or modified
        }

        let cacheURL = cacheFileURL(for: path)

        guard let data = try? Data(contentsOf: cacheURL),
              var cacheEntry = try? JSONDecoder().decode(CacheEntry.self, from: data) else {
            return nil
        }

        let now = Date()
        let cacheAge = now.timeIntervalSince(cacheEntry.scanTime)

        // Check if cache is expired
        let isExpired = cacheAge > ttl
        let isInGraceWindow = cacheAge <= (ttl + graceWindow)

        // Check if directory has been modified since cache was created
        let currentModTime = getModTime(for: path)
        let hasModTimeChanged = currentModTime != nil && currentModTime! > cacheEntry.modTime

        // Update needsRefresh flag
        if isExpired || hasModTimeChanged {
            cacheEntry = CacheEntry(
                entries: cacheEntry.entries,
                largeFiles: cacheEntry.largeFiles,
                totalSize: cacheEntry.totalSize,
                totalFiles: cacheEntry.totalFiles,
                modTime: cacheEntry.modTime,
                scanTime: cacheEntry.scanTime,
                needsRefresh: true
            )
        }

        // Return cache entry if it's valid or within grace window
        if !isExpired || isInGraceWindow {
            memoryCache.setObject(MemoryCacheEntry(result: cacheEntry), forKey: key)
            return cacheEntry
        }

        // Cache is too old, delete it
        try? fileManager.removeItem(at: cacheURL)
        memoryCache.removeObject(forKey: key)
        return nil
    }

    func set(path: String, entry: CacheEntry) {
        let key = path as NSString
        memoryCache.setObject(MemoryCacheEntry(result: entry), forKey: key)

        let cacheURL = cacheFileURL(for: path)

        guard let data = try? JSONEncoder().encode(entry) else {
            return
        }

        try? data.write(to: cacheURL)
    }

    func invalidate(path: String) {
        let key = path as NSString
        memoryCache.removeObject(forKey: key)

        let cacheURL = cacheFileURL(for: path)
        try? fileManager.removeItem(at: cacheURL)
    }

    func clear() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cleanupExpired() {
        let now = Date()
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modificationDate = attributes[.modificationDate] as? Date else {
                continue
            }

            let age = now.timeIntervalSince(modificationDate)
            if age > (ttl + graceWindow) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }
}
