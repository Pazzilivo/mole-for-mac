import Foundation

/// Cached scan result with metadata
struct CacheEntry: Codable {
    let entries: [DirEntry]
    let largeFiles: [FileEntry]
    let totalSize: Int64
    let totalFiles: Int64
    let modTime: Date
    let scanTime: Date
    let needsRefresh: Bool
}