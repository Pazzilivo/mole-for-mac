import Foundation

/// Large file entry for tracking individual files
struct FileEntry: Codable {
    let name: String
    let path: String
    let size: Int64
    let lastAccess: Date?

    init(name: String, path: String, size: Int64, lastAccess: Date? = nil) {
        self.name = name
        self.path = path
        self.size = size
        self.lastAccess = lastAccess
    }
}

/// Extension for heap operations (Top-N largest files)
extension FileEntry: Comparable {
    static func < (lhs: FileEntry, rhs: FileEntry) -> Bool {
        return lhs.size < rhs.size
    }
}