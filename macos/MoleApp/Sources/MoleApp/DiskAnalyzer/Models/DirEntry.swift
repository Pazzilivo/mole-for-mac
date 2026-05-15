import Foundation

/// Directory or file entry for disk analysis results
struct DirEntry: Codable, Identifiable {
    let name: String
    let path: String
    let size: Int64
    let isDir: Bool
    let lastAccess: Date?

    var id: String { path }

    /// Special size value for overview entries that haven't been measured yet
    static let pendingSize: Int64 = -1
}

/// Extension for heap operations (Top-N largest entries)
extension DirEntry: Comparable {
    static func < (lhs: DirEntry, rhs: DirEntry) -> Bool {
        return lhs.size < rhs.size
    }
}