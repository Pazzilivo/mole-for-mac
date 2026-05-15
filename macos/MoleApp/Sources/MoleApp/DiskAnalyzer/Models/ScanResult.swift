import Foundation

/// Complete scan result for a directory
struct ScanResult: Codable {
    let entries: [DirEntry]
    let largeFiles: [FileEntry]
    let totalSize: Int64
    let totalFiles: Int64
}