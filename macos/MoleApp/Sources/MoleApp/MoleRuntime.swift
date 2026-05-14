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

    func runMole(_ arguments: [String], timeout: TimeInterval = 30, sudo: Bool = false) async throws -> MoleCommandResult {
        try checkRuntime()
        return try await run(executable: moleExecutable, arguments: arguments, timeout: timeout, sudo: sudo)
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

    private func run(executable: URL, arguments: [String], timeout: TimeInterval, sudo: Bool = false) async throws -> MoleCommandResult {
        return try await runStreamed(executable: executable, arguments: arguments, timeout: timeout, useSudo: sudo)
    }

    func runStreamed(executable: URL? = nil, arguments: [String], timeout: TimeInterval, useSudo: Bool = false, onOutput: (@Sendable (String) -> Void)? = nil) async throws -> MoleCommandResult {
        let exec = executable ?? moleExecutable
        guard FileManager.default.isExecutableFile(atPath: exec.path) else {
            throw MoleRuntimeError.missingExecutable(exec)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let completion = CompletionGate()
            let stdoutData = PipeDataBuffer()
            let stderrData = PipeDataBuffer()

            if useSudo {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = [exec.path] + arguments
            } else {
                process.executableURL = exec
                process.arguments = arguments
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stdoutData.append(chunk)
                if let callback = onOutput, let text = String(data: chunk, encoding: .utf8) {
                    callback(text)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stderrData.append(chunk)
                if let callback = onOutput, let text = String(data: chunk, encoding: .utf8) {
                    callback(text)
                }
            }

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

    @Published var hasFullDiskAccess: Bool = true
    @Published var isAdmin: Bool = false
    @Published var analyzeProgress: String = ""

    @Published var cleanState: LoadState = .idle
    @Published var cleanProgress: String = ""
    @Published var cleanOutput: String = ""
    @Published var cleanCategories: [CleanCategory] = []

    private var outputBuffer = ""
    private var flushTimer: Timer?
    @Published var cleanTotalSize: String = "--"

    @Published var updateState: LoadState = .idle
    @Published var latestVersion: String = ""
    @Published var updateProgress: String = ""
    @Published var updateDownloadPercent: Double = 0
    private var updateDownloadURL: String = ""

    @Published var status: StatusSnapshot?
    @Published var apps: [AppEntry] = []
    @Published var analysis: AnalyzeOutput?
    @Published var optimizePlan: OptimizePlan?
    @Published var activity: [ActivityLine] = []
    @Published var operationLog: [OperationLogEntry] = []
    @Published var deletionLog: [DeletionLogEntry] = []

    let runtime = MoleRuntime()
    private var useSudo: Bool { isAdmin }

    private func startFlushTimer(target: ReferenceWritableKeyPath<MoleAppModel, String>) {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushBuffer(to: target)
            }
        }
    }

    private func stopFlushTimer(target: ReferenceWritableKeyPath<MoleAppModel, String>) {
        flushBuffer(to: target)
        flushTimer?.invalidate()
        flushTimer = nil
    }

    private func flushBuffer(to target: ReferenceWritableKeyPath<MoleAppModel, String>) {
        guard !outputBuffer.isEmpty else { return }
        let text = outputBuffer
        outputBuffer = ""
        self[keyPath: target] += text
    }

    private func bufferOutput(_ text: String, progress: ReferenceWritableKeyPath<MoleAppModel, String>) {
        let line = stripANSI(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        outputBuffer += line + "\n"
        self[keyPath: progress] = line
    }

    func refreshDashboard() async {
        checkFullDiskAccess()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshStatus() }
            group.addTask { await self.refreshApps() }
        }
    }

    func checkFullDiskAccess() {
        let testPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")
        hasFullDiskAccess = FileManager.default.isReadableFile(atPath: testPath.path)
    }

    func requestAdmin() {
        let script = NSAppleScript(source: """
        do shell script "sudo -v" with administrator privileges
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if error == nil {
            isAdmin = true
            checkFullDiskAccess()
            // Keep sudo session alive
            startSudoKeeper()
            Task { await refreshDashboard() }
        }
    }

    private func startSudoKeeper() {
        Timer.scheduledTimer(withTimeInterval: 240, repeats: true) { _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-v"]
            try? process.run()
        }
    }

    func refreshStatus() async {
        statusState = .loading
        do {
            let result = try await runtime.runMole(["status", "--json"], timeout: 20, sudo: useSudo)
            let decoder = JSONDecoder()
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let string = try container.decode(String.self)
                if let date = isoFormatter.date(from: string) { return date }
                let fallback = ISO8601DateFormatter()
                fallback.formatOptions = [.withInternetDateTime]
                if let date = fallback.date(from: string) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(string)")
            }
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
            let result = try await runtime.runMole(["uninstall", "--list"], timeout: 45, sudo: useSudo)
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
        analyzeProgress = ""
        outputBuffer = ""
        startFlushTimer(target: \.analyzeProgress)
        do {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let result = try await runtime.runStreamed(
                arguments: ["analyze", "--json", home],
                timeout: 300,
                useSudo: useSudo,
                onOutput: { [weak self] text in
                    Task { @MainActor in
                        self?.bufferOutput(text, progress: \.analyzeProgress)
                    }
                }
            )
            stopFlushTimer(target: \.analyzeProgress)
            analysis = try JSONDecoder().decode(AnalyzeOutput.self, from: result.stdout)
            analyzeState = .ready
            append("Home analyzed", detail: "Disk scan finished for \(home).")
        } catch {
            stopFlushTimer(target: \.analyzeProgress)
            analyzeState = .failed(error.localizedDescription)
            append("Disk analysis failed", detail: error.localizedDescription, isError: true)
        }
    }

    func runCleanScan() async {
        cleanState = .loading
        cleanProgress = ""
        cleanOutput = ""
        cleanCategories = []
        cleanTotalSize = "--"
        outputBuffer = ""
        startFlushTimer(target: \.cleanOutput)
        do {
            let result = try await runtime.runStreamed(
                arguments: ["clean", "--dry-run"],
                timeout: 600,
                useSudo: useSudo,
                onOutput: { [weak self] text in
                    Task { @MainActor in
                        self?.bufferOutput(text, progress: \.cleanProgress)
                    }
                }
            )
            stopFlushTimer(target: \.cleanOutput)
            let output = String(data: result.stdout, encoding: .utf8) ?? ""
            cleanOutput += stripANSI(output)
            parseCleanOutput(cleanOutput)
            cleanState = .ready
            append("Clean scan finished", detail: "Found \(cleanCategories.count) categories, \(cleanTotalSize) reclaimable.")
        } catch {
            stopFlushTimer(target: \.cleanOutput)
            cleanState = .failed(error.localizedDescription)
            append("Clean scan failed", detail: error.localizedDescription, isError: true)
        }
    }

    func runCleanApply() async {
        cleanState = .loading
        cleanProgress = "Cleaning..."
        outputBuffer = ""
        startFlushTimer(target: \.cleanOutput)
        do {
            let result = try await runtime.runStreamed(
                arguments: ["clean"],
                timeout: 600,
                useSudo: useSudo,
                onOutput: { [weak self] text in
                    Task { @MainActor in
                        self?.bufferOutput(text, progress: \.cleanProgress)
                    }
                }
            )
            stopFlushTimer(target: \.cleanOutput)
            cleanCategories = []
            cleanTotalSize = "--"
            cleanState = .idle
            append("Clean completed", detail: "Cleanup finished successfully.")
        } catch {
            stopFlushTimer(target: \.cleanOutput)
            cleanState = .failed(error.localizedDescription)
            append("Clean failed", detail: error.localizedDescription, isError: true)
        }
    }

    private func parseCleanOutput(_ output: String) {
        var categories: [CleanCategory] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.contains("User app cache") {
                if let size = extractSize(from: trimmed) {
                    categories.append(CleanCategory(name: "User App Cache", size: size, detail: extractCount(from: trimmed), icon: "archivebox", color: .blue))
                }
            } else if trimmed.contains("User app logs") {
                if let size = extractSize(from: trimmed) {
                    categories.append(CleanCategory(name: "User App Logs", size: size, detail: extractCount(from: trimmed), icon: "doc.text", color: .orange))
                }
            } else if trimmed.contains("Darwin user temp") {
                if let size = extractSize(from: trimmed) {
                    categories.append(CleanCategory(name: "Temp Files", size: size, detail: extractCount(from: trimmed), icon: "clock", color: .purple))
                }
            } else if trimmed.contains("Darwin user cache") {
                if let size = extractSize(from: trimmed) {
                    categories.append(CleanCategory(name: "System Cache", size: size, detail: extractCount(from: trimmed), icon: "internaldrive", color: .teal))
                }
            } else if trimmed.contains("Trash") && trimmed.contains("empty") {
                categories.append(CleanCategory(name: "Trash", size: "--", detail: "Already empty", icon: "trash", color: .green))
            } else if trimmed.contains("orphan") || trimmed.contains("Orphan") {
                if let size = extractSize(from: trimmed) {
                    categories.append(CleanCategory(name: "Orphan Files", size: size, detail: "", icon: "questionmark.folder", color: .red))
                }
            } else if trimmed.contains("Xcode") || trimmed.contains("DerivedData") {
                if let size = extractSize(from: trimmed) {
                    categories.append(CleanCategory(name: "Xcode Cache", size: size, detail: "", icon: "hammer", color: .blue))
                }
            } else if trimmed.contains("brew") || trimmed.contains("Homebrew") {
                if let size = extractSize(from: trimmed) {
                    categories.append(CleanCategory(name: "Homebrew Cache", size: size, detail: "", icon: "mug", color: .orange))
                }
            }
        }

        let totalBytes = categories.compactMap { parseSizeToBytes($0.size) }.reduce(0, +)
        cleanTotalSize = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        cleanCategories = categories
    }

    private func extractSize(from line: String) -> String? {
        let pattern = #"(\d+\.?\d*\s*[KMGT]?B)"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        return String(line[range])
    }

    private func extractCount(from line: String) -> String {
        let pattern = #"(\d+)\s*items?"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return "" }
        return String(line[range])
    }

    private func parseSizeToBytes(_ size: String) -> Int64 {
        let parts = size.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return 0 }
        let unit = String(parts[1])
        switch unit {
        case "KB": return Int64(value * 1024)
        case "MB": return Int64(value * 1024 * 1024)
        case "GB": return Int64(value * 1024 * 1024 * 1024)
        case "TB": return Int64(value * 1024 * 1024 * 1024 * 1024)
        default: return Int64(value)
        }
    }

    func refreshOptimizePlan() async {
        optimizeState = .loading
        do {
            let result = try await runtime.runMole(["optimize", "--plan-json"], timeout: 20, sudo: useSudo)
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

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func checkForUpdates() async {
        updateState = .loading
        do {
            let checkURL = URL(string: "https://github.com/Pazzilivo/mole-for-mac/releases/latest")!
            var request = URLRequest(url: checkURL)
            request.setValue("Mole-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let finalURL = response.url?.absoluteString,
                  finalURL.contains("/tag/") else {
                updateState = .idle
                return
            }
            let tag = finalURL.components(separatedBy: "/tag/").last ?? ""
            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            latestVersion = remote

            if remote.compare(currentVersion, options: .numeric) == .orderedDescending {
                updateDownloadURL = "https://github.com/Pazzilivo/mole-for-mac/releases/download/\(tag)/Mole-\(remote).zip"
                updateState = .ready
            } else {
                updateState = .idle
            }
        } catch {
            updateState = .failed("Update check failed: \(error.localizedDescription)")
        }
    }

    func performUpdate() async {
        guard !updateDownloadURL.isEmpty else { return }
        updateState = .loading
        updateProgress = "Downloading..."
        updateDownloadPercent = 0
        do {
            let zipURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Mole-update.zip")
            let updateDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Mole-update")

            try? FileManager.default.removeItem(at: zipURL)
            try? FileManager.default.removeItem(at: updateDir)

            // Download with progress
            let downloadDelegate = DownloadProgressDelegate()
            downloadDelegate.onProgress = { [weak self] percent in
                Task { @MainActor in
                    self?.updateDownloadPercent = percent
                    self?.updateProgress = "Downloading... \(Int(percent * 100))%"
                }
            }
            let session = URLSession(configuration: .default, delegate: downloadDelegate, delegateQueue: nil)
            let (zipLocation, response) = try await session.download(from: URL(string: updateDownloadURL)!)
            let expectedLength = response.expectedContentLength
            if expectedLength > 0 {
                let sizeStr = ByteCountFormatter.string(fromByteCount: expectedLength, countStyle: .file)
                updateProgress = "Downloaded \(sizeStr)"
            }

            try FileManager.default.moveItem(at: zipLocation, to: zipURL)

            updateProgress = "Extracting..."

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zipURL.path, updateDir.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                throw NSError(domain: "Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "Extraction failed"])
            }

            let contents = try FileManager.default.contentsOfDirectory(at: updateDir, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                throw NSError(domain: "Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "No app found in archive"])
            }

            let currentApp = Bundle.main.bundleURL
            let currentAppName = currentApp.lastPathComponent
            let newAppDest = currentApp.deletingLastPathComponent().appendingPathComponent(currentAppName)

            // Write a shell script that replaces and relaunches after the app exits
            let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Mole-relink.sh")
            let script = """
            #!/bin/bash
            # Wait for the old app to exit
            while pgrep -f "\(currentApp.path)" > /dev/null 2>&1; do
                sleep 0.5
            done
            # Trash old app
            mv "\(currentApp.path)" "$HOME/.Trash/\(currentAppName)" 2>/dev/null
            # Copy new app
            cp -R "\(newApp.path)" "\(newAppDest.path)"
            # Remove quarantine
            /usr/bin/xattr -cr "\(newAppDest.path)"
            # Cleanup
            rm -rf "\(zipURL.path)" "\(updateDir.path)" "$0"
            # Relaunch
            open "\(newAppDest.path)"
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptURL.path]
            try chmod.run()
            chmod.waitUntilExit()

            updateProgress = "Restarting..."

            // Launch the script in background, then terminate
            let runner = Process()
            runner.executableURL = URL(fileURLWithPath: "/bin/bash")
            runner.arguments = [scriptURL.path]
            try runner.run()
            // Detach so it survives app termination
            try? runner.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            updateState = .failed(error.localizedDescription)
            updateProgress = ""
            updateDownloadPercent = 0
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

private func stripANSI(_ text: String) -> String {
    text.replacingOccurrences(of: #"\u{001B}\[[0-9;]*m"#, with: "", options: .regularExpression)
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    var onProgress: ((Double) -> Void)?
    private var total: Int64 = 0

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            total = totalBytesExpectedToWrite
            onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }
}
