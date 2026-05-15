import Foundation

/// Enum for scan items during processing
enum ScanItem {
    case dir(Int64, String, String, Bool)  // (size, name, path, isFolded)
    case file(Int64, String, String, Date?)  // (size, name, path, lastAccess)
}