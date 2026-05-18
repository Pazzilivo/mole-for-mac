import Foundation

final class ProcessCollector: MetricCollector {
    typealias Output = [ProcessEntry]

    func collect() async throws -> [ProcessEntry] {
        try await Task.detached(priority: .utility) { () throws -> [ProcessEntry] in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-Aceo", "pid=,ppid=,pcpu=,pmem=,comm=", "-r"]
            process.standardOutput = pipe

            do {
                try process.run()
            } catch {
                throw NSError(domain: "ProcessCollector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to execute process: \(error.localizedDescription)"])
            }

            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            guard !process.isRunning else {
                process.terminate()
                return []
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "ProcessCollector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode output"])
            }

            let entries = Self.parsePSOutput(output)
            return Array(entries.prefix(5))
        }.value
    }

    private static func parsePSOutput(_ output: String) -> [ProcessEntry] {
        var entries: [ProcessEntry] = []

        for line in output.components(separatedBy: "\n").dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let fields = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 5,
                  let pid = Int(fields[0]),
                  let ppid = Int(fields[1]),
                  let cpu = Double(fields[2]),
                  let memory = Double(fields[3]) else {
                continue
            }

            // Join remaining fields as command name (in case command has spaces)
            let command = fields.dropFirst(4).joined(separator: " ")

            // Extract the process name (first part of command or the full command if no spaces)
            let name = command.components(separatedBy: " ").first ?? command

            entries.append(ProcessEntry(
                pid: pid,
                ppid: ppid,
                name: name,
                command: command,
                cpu: cpu,
                memory: memory
            ))
        }

        return entries
    }
}
