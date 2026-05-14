import Foundation
import SwiftUI

struct MoleCommandResult {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

enum MoleRuntimeError: LocalizedError {
    case missingRuntime(URL)
    case missingExecutable(URL)
    case commandFailed(Int32, String)
    case timedOut
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case let .missingRuntime(url):
            return "Bundled Mole runtime was not found at \(url.path)."
        case let .missingExecutable(url):
            return "Executable was not found at \(url.path)."
        case let .commandFailed(code, message):
            return "Mole command failed with exit code \(code): \(message)"
        case .timedOut:
            return "Mole command timed out."
        case let .invalidOutput(message):
            return "Mole returned invalid output: \(message)"
        }
    }
}

final class MoleRuntime {
    let root: URL

    init(resourceRoot: URL? = Bundle.main.resourceURL) {
        self.root = (resourceRoot ?? URL(fileURLWithPath: "."))
            .appendingPathComponent("MoleRuntime", isDirectory: true)
    }

    var moleExecutable: URL {
        root.appendingPathComponent("mole")
    }

    var moExecutable: URL {
        root.appendingPathComponent("mo")
    }

    var statusExecutable: URL {
        root.appendingPathComponent("bin/status-go")
    }

    var analyzeExecutable: URL {
        root.appendingPathComponent("bin/analyze-go")
    }

    var operationsLog: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/mole/operations.log")
    }

    var deletionsLog: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/mole/deletions.log")
    }

    func checkRuntime() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw MoleRuntimeError.missingRuntime(root)
        }
        guard FileManager.default.isExecutableFile(atPath: moleExecutable.path) else {
            throw MoleRuntimeError.missingExecutable(moleExecutable)
        }
    }

    func runMole(_ arguments: [String], timeout: TimeInterval = 30) async throws -> MoleCommandResult {
        try checkRuntime()
        return try await run(executable: moleExecutable, arguments: arguments, timeout: timeout)
    }

    func runtimeChecks() -> [RuntimeCheck] {
        [
            RuntimeCheck(
                title: "Bundled runtime",
                detail: root.path,
                isAvailable: FileManager.default.fileExists(atPath: root.path)
            ),
            RuntimeCheck(
                title: "CLI router",
                detail: moleExecutable.path,
                isAvailable: FileManager.default.isExecutableFile(atPath: moleExecutable.path)
            ),
            RuntimeCheck(
                title: "Status helper",
                detail: statusExecutable.path,
                isAvailable: FileManager.default.isExecutableFile(atPath: statusExecutable.path)
            ),
            RuntimeCheck(
                title: "Analyze helper",
                detail: analyzeExecutable.path,
                isAvailable: FileManager.default.isExecutableFile(atPath: analyzeExecutable.path)
            )
        ]
    }

    private func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> MoleCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MoleRuntimeError.missingExecutable(executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let completion = CompletionGate()
            let stdoutData = PipeDataBuffer()
            let stderrData = PipeDataBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stdoutData.append(chunk)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stderrData.append(chunk)
            }

            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = root
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = nil

            var environment = ProcessInfo.processInfo.environment
            environment["MOLE_GUI"] = "1"
            environment["TERM"] = "dumb"
            environment["LC_ALL"] = "C"
            environment["LANG"] = "C"
            process.environment = environment

            let timeoutWork = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
                completion.resume {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: MoleRuntimeError.timedOut)
                }
            }

            process.terminationHandler = { finishedProcess in
                timeoutWork.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let stdout = stdoutData.snapshot()
                let stderr = stderrData.snapshot()

                let result = MoleCommandResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: finishedProcess.terminationStatus
                )

                completion.resume {
                    if result.exitCode == 0 {
                        continuation.resume(returning: result)
                    } else {
                        let message = String(data: stderr, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(
                            throwing: MoleRuntimeError.commandFailed(
                                result.exitCode,
                                message?.isEmpty == false ? message! : "No error output"
                            )
                        )
                    }
                }
            }

            do {
                try process.run()
                DispatchQueue.global(qos: .utility)
                    .asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            } catch {
                timeoutWork.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                completion.resume {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class CompletionGate {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ block: () -> Void) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()
        block()
    }
}

private final class PipeDataBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}

@MainActor
final class MoleAppModel: ObservableObject {
    @Published var statusState: LoadState = .idle
    @Published var appsState: LoadState = .idle
    @Published var analyzeState: LoadState = .idle
    @Published var optimizeState: LoadState = .idle
    @Published var logsState: LoadState = .idle

    @Published var status: StatusSnapshot?
    @Published var apps: [AppEntry] = []
    @Published var analysis: AnalyzeOutput?
    @Published var optimizePlan: OptimizePlan?
    @Published var activity: [ActivityLine] = []
    @Published var operationLog: [OperationLogEntry] = []
    @Published var deletionLog: [DeletionLogEntry] = []

    let runtime = MoleRuntime()

    func refreshDashboard() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshStatus() }
            group.addTask { await self.refreshApps() }
        }
    }

    func refreshStatus() async {
        statusState = .loading
        do {
            let result = try await runtime.runMole(["status", "--json"], timeout: 20)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            status = try decoder.decode(StatusSnapshot.self, from: result.stdout)
            statusState = .ready
            append("Status refreshed", detail: "System metrics loaded from bundled Mole runtime.")
        } catch {
            statusState = .failed(error.localizedDescription)
            append("Status unavailable", detail: error.localizedDescription, isError: true)
        }
    }

    func refreshApps() async {
        appsState = .loading
        do {
            let result = try await runtime.runMole(["uninstall", "--list"], timeout: 45)
            apps = try JSONDecoder().decode([AppEntry].self, from: result.stdout)
            appsState = .ready
            append("Applications scanned", detail: "\(apps.count) apps found.")
        } catch {
            appsState = .failed(error.localizedDescription)
            append("Application scan failed", detail: error.localizedDescription, isError: true)
        }
    }

    func analyzeHome() async {
        analyzeState = .loading
        do {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let result = try await runtime.runMole(["analyze", "--json", home], timeout: 90)
            analysis = try JSONDecoder().decode(AnalyzeOutput.self, from: result.stdout)
            analyzeState = .ready
            append("Home analyzed", detail: "Disk scan finished for \(home).")
        } catch {
            analyzeState = .failed(error.localizedDescription)
            append("Disk analysis failed", detail: error.localizedDescription, isError: true)
        }
    }

    func refreshOptimizePlan() async {
        optimizeState = .loading
        do {
            let result = try await runtime.runMole(["optimize", "--plan-json"], timeout: 20)
            optimizePlan = try JSONDecoder().decode(OptimizePlan.self, from: result.stdout)
            optimizeState = .ready
            append("Optimize plan loaded", detail: "\(optimizePlan?.optimizations.count ?? 0) tasks available.")
        } catch {
            optimizeState = .failed(error.localizedDescription)
            append("Optimize plan failed", detail: error.localizedDescription, isError: true)
        }
    }

    func refreshLogs() {
        logsState = .loading
        do {
            operationLog = Array(try Self.readLastLines(at: runtime.operationsLog, maxLines: 160)
                .compactMap(Self.parseOperationLogLine)
                .reversed())
            deletionLog = Array(try Self.readLastLines(at: runtime.deletionsLog, maxLines: 160)
                .compactMap(Self.parseDeletionLogLine)
                .reversed())
            logsState = .ready
            append("Logs refreshed", detail: "\(operationLog.count) operation entries and \(deletionLog.count) deletion entries loaded.")
        } catch {
            logsState = .failed(error.localizedDescription)
            append("Log refresh failed", detail: error.localizedDescription, isError: true)
        }
    }

    func installUserCLI() {
        do {
            try runtime.checkRuntime()
            let fileManager = FileManager.default
            let binDir = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin", isDirectory: true)
            try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)

            let link = binDir.appendingPathComponent("mo")
            if fileManager.fileExists(atPath: link.path) || fileManager.destinationOfSymbolicLinkExists(at: link) {
                try fileManager.removeItem(at: link)
            }
            try fileManager.createSymbolicLink(at: link, withDestinationURL: runtime.moExecutable)
            append("Command installed", detail: "Created \(link.path). Add ~/.local/bin to PATH if needed.")
        } catch {
            append("Command install failed", detail: error.localizedDescription, isError: true)
        }
    }

    private static func readLastLines(at url: URL, maxLines: Int) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return Array(lines.suffix(maxLines)).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func parseOperationLogLine(_ line: String) -> OperationLogEntry? {
        if line.hasPrefix("#") {
            return OperationLogEntry(
                timestamp: "",
                command: "session",
                action: "MARK",
                path: line.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces),
                detail: "",
                rawLine: line,
                isSession: true
            )
        }

        let pattern = #"^\[(.*?)\] \[(.*?)\] ([A-Z_-]+) (.*?)(?: \((.*)\))?$"#
        guard let match = line.firstMatch(pattern: pattern) else {
            return OperationLogEntry(
                timestamp: "",
                command: "unknown",
                action: "RAW",
                path: line,
                detail: "",
                rawLine: line,
                isSession: false
            )
        }

        return OperationLogEntry(
            timestamp: match[safe: 1] ?? "",
            command: match[safe: 2] ?? "",
            action: match[safe: 3] ?? "",
            path: match[safe: 4] ?? "",
            detail: match[safe: 5] ?? "",
            rawLine: line,
            isSession: false
        )
    }

    private static func parseDeletionLogLine(_ line: String) -> DeletionLogEntry? {
        let columns = line.components(separatedBy: "\t")
        guard columns.count >= 5 else {
            return DeletionLogEntry(
                timestamp: "",
                mode: "unknown",
                sizeKB: "",
                status: "RAW",
                path: line,
                rawLine: line
            )
        }
        return DeletionLogEntry(
            timestamp: columns[0],
            mode: columns[1],
            sizeKB: columns[2],
            status: columns[3],
            path: columns.dropFirst(4).joined(separator: "\t"),
            rawLine: line
        )
    }

    private func append(_ title: String, detail: String, isError: Bool = false) {
        activity.insert(ActivityLine(title: title, detail: detail, isError: isError), at: 0)
        if activity.count > 8 {
            activity.removeLast(activity.count - 8)
        }
    }
}

private extension FileManager {
    func destinationOfSymbolicLinkExists(at url: URL) -> Bool {
        (try? destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}

private extension String {
    func firstMatch(pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = expression.firstMatch(in: self, range: range) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: self) else {
                return ""
            }
            return String(self[swiftRange])
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
