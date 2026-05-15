import Foundation

/// JSON output for disk analysis (DiskAnalyzer module)
struct DiskAnalyzeOutput: Codable {
    let path: String
    let overview: Bool
    let entries: [DiskAnalyzeEntry]
    let largeFiles: [DiskAnalyzeFileEntry]?
    let totalSize: Int64
    let totalFiles: Int64?
}

/// Individual entry in JSON output (DiskAnalyzer module)
struct DiskAnalyzeEntry: Codable {
    let name: String
    let path: String
    let size: Int64
    let isDir: Bool
    let insight: Bool?
    let cleanable: Bool?
    let lastAccess: String?
}

/// Large file entry in JSON output (DiskAnalyzer module)
struct DiskAnalyzeFileEntry: Codable {
    let name: String
    let path: String
    let size: Int64
}