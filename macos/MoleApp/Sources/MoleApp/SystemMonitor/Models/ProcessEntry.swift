import Foundation

// ProcessEntry
struct ProcessEntry: Codable, Identifiable {
    let pid: Int
    let ppid: Int
    let name: String
    let command: String
    let cpu: Double
    let memory: Double
    var id: Int { pid }
}