import Foundation

/// Scan configuration constants
struct ScanConfig {
    /// Maximum number of directory entries to display
    static let maxEntries = 30

    /// Maximum number of large files to track
    static let maxLargeFiles = 20

    /// Bar width for UI display
    static let barWidth = 24

    /// Minimum file size for Spotlight analysis (100MB)
    static let spotlightMinFileSize: Int64 = 100 << 20

    /// Minimum file size for large file warmup (1MB)
    static let largeFileWarmupMinSize: Int64 = 1 << 20

    /// Default viewport size for UI
    static let defaultViewport = 12

    /// Overview cache TTL (7 days)
    static let overviewCacheTTL: TimeInterval = 7 * 24 * 3600

    /// Overview cache file name
    static let overviewCacheFile = "overview_sizes.json"

    /// Timeout for du command (30 seconds)
    static let duTimeout: TimeInterval = 30

    /// Timeout for mdls command (5 seconds)
    static let mdlsTimeout: TimeInterval = 5

    /// Maximum concurrent overview scans
    static let maxConcurrentOverview = 8

    /// Batch update size for UI
    static let batchUpdateSize = 100

    /// Grace period for cache modification time (30 minutes)
    static let cacheModTimeGrace: TimeInterval = 30 * 60

    /// Cache reuse window (24 hours)
    static let cacheReuseWindow: TimeInterval = 24 * 3600

    /// Stale cache TTL (3 days)
    static let staleCacheTTL: TimeInterval = 3 * 24 * 3600

    /// Minimum worker pool size
    static let minWorkers = 2

    /// Maximum worker pool size
    static let maxWorkers = 12

    /// CPU multiplier for worker pool
    static let cpuMultiplier = 1

    /// Maximum directory workers
    static let maxDirWorkers = 6

    /// Open command timeout (10 seconds)
    static let openCommandTimeout: TimeInterval = 10

    /// Scan send timeout (100ms)
    static let scanSendTimeout: TimeInterval = 0.1

    /// UI tick interval (100ms)
    static let uiTickInterval: TimeInterval = 0.1
}