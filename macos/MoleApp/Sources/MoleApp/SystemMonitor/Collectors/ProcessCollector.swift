import Foundation

final class ProcessCollector: MetricCollector {
    typealias Output = [ProcessEntry]

    func collect() async throws -> [ProcessEntry] {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-Aceo", "pid=,ppid=,pcpu=,pmem=,comm=", "-r"]
            process.standardOutput = pipe

            // Add timeout to prevent continuation leak
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                if Task.isCancelled == false {
                    process.terminate()
                    continuation.resume(throwing: NSError(domain: "ProcessCollector", code: 2, userInfo: [NSLocalizedDescriptionKey: "Process timeout"]))
                }
            }

            // Use terminationHandler instead of waitUntilExit (Fix warning)
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()

                guard let output = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: NSError(domain: "ProcessCollector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode output"]))
                    return
                }

                let entries = self.parsePSOutput(output)
                continuation.resume(returning: Array(entries.prefix(5)))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: NSError(domain: "ProcessCollector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to execute process: \(error.localizedDescription)"]))
            }
        }
    }

    private func parsePSOutput(_ output: String) -> [ProcessEntry] {
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