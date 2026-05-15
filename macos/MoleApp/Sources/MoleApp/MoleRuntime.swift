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

    var cleanListFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mole/clean-list.txt")
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
                process.arguments = ["-n", exec.path] + arguments
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

    @Published var uninstallState: LoadState = .idle
    @Published var uninstallProgress: String = ""

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
    private var useSudo: Bool { false }

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
            process.arguments = ["-n", "-v"]
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

    func uninstallApp(_ app: AppEntry) async {
        let appName = app.uninstallName ?? app.name
        uninstallState = .loading
        uninstallProgress = "Uninstalling \(appName)..."
        outputBuffer = ""
        startFlushTimer(target: \.uninstallProgress)
        do {
            let molePath = runtime.moleExecutable.path
            let shellCommand = useSudo
                ? "printf 'y\n\n' | sudo \(molePath) uninstall \(appName) 2>&1"
                : "printf 'y\n\n' | \(molePath) uninstall \(appName) 2>&1"

            // Run on background thread to avoid blocking UI
            let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/bash")
                    process.arguments = ["-c", shellCommand]
                    process.currentDirectoryURL = self.runtime.root

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    let outputBuffer = PipeDataBuffer()
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { return }
                        outputBuffer.append(chunk)
                        if let text = String(data: chunk, encoding: .utf8) {
                            Task { @MainActor in
                                self.bufferOutput(text, progress: \.uninstallProgress)
                            }
                        }
                    }

                    do {
                        try process.run()
                        process.waitUntilExit()
                        pipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(returning: process.terminationStatus)
                    } catch {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
            }

            stopFlushTimer(target: \.uninstallProgress)

            if result == 0 {
                uninstallState = .idle
                uninstallProgress = ""
                append("Uninstalled \(appName)", detail: "App and leftovers moved to Trash.")
                await refreshApps()
            } else {
                uninstallState = .failed("Uninstall exited with code \(result)")
                uninstallProgress = ""
                append("Uninstall failed", detail: "Exit code \(result)", isError: true)
            }
        } catch {
            stopFlushTimer(target: \.uninstallProgress)
            uninstallState = .failed(error.localizedDescription)
            uninstallProgress = ""
            append("Uninstall failed", detail: error.localizedDescription, isError: true)
        }
    }

    func runCleanScan() async {
        cleanState = .loading
        cleanProgress = ""
        cleanOutput = ""
        cleanCategories = []
        cleanTotalSize = "--"
        outputBuffer = ""

        var allOutput = ""
        let lock = NSLock()

        do {
            let result = try await runtime.runStreamed(
                arguments: ["clean", "--dry-run"],
                timeout: 600,
                useSudo: useSudo,
                onOutput: { text in
                    let cleaned = stripANSI(text)
                    lock.lock()
                    allOutput += cleaned
                    lock.unlock()
                    let line = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { return }
                    Task { @MainActor in
                        self.cleanProgress = line
                    }
                }
            )
            // Also grab any remaining stdout
            let remaining = String(data: result.stdout, encoding: .utf8) ?? ""
            lock.lock()
            allOutput += remaining
            lock.unlock()

            cleanOutput = allOutput
            cleanProgress = ""
            parseCleanOutput(cleanOutput)
            cleanState = .ready
            append("Clean scan finished", detail: "Found \(cleanCategories.count) categories, \(cleanTotalSize) reclaimable.")
        } catch {
            cleanProgress = ""
            cleanState = .failed(error.localizedDescription)
            append("Clean scan failed", detail: error.localizedDescription, isError: true)
        }
    }

    func runCleanApply() async {
        cleanState = .loading
        cleanProgress = "Cleaning..."
        outputBuffer = ""
        do {
            let _ = try await runtime.runStreamed(
                arguments: ["clean"],
                timeout: 600,
                useSudo: useSudo,
                onOutput: { text in
                    let line = stripANSI(text).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { return }
                    Task { @MainActor in
                        self.cleanProgress = line
                    }
                }
            )
            cleanCategories = []
            cleanTotalSize = "--"
            cleanProgress = ""
            cleanOutput = ""
            cleanState = .idle
            append("Clean completed", detail: "Cleanup finished successfully.")
        } catch {
            cleanProgress = ""
            cleanState = .failed(error.localizedDescription)
            append("Clean failed", detail: error.localizedDescription, isError: true)
        }
    }

    private func parseCleanOutput(_ output: String) {
        var categories: [CleanCategory] = []
        var currentCategory: CleanCategory?
        var currentFiles: [String] = []
        let sectionHeaders = [
            "User essentials": ("User App Cache", "archivebox", Color.blue),
            "App caches": ("App Caches", "internaldrive", Color.teal),
            "Dev caches": ("Dev Caches", "hammer", Color.blue),
            "System caches": ("System Caches", "gearshape", Color.purple),
        ]

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Section headers like "➤ User essentials"
            if let section = sectionHeaders.first(where: { trimmed.contains($0.key) }) {
                // Flush previous category
                if var cat = currentCategory {
                    cat.files = currentFiles
                    categories.append(cat)
                }
                currentCategory = nil
                currentFiles = []
                continue
            }

            // Category lines with size (→ prefix)
            if trimmed.hasPrefix("→") || trimmed.contains("→") {
                // Flush previous
                if var cat = currentCategory {
                    cat.files = currentFiles
                    categories.append(cat)
                }
                currentFiles = []

                if let size = extractSize(from: trimmed) {
                    if trimmed.contains("User app cache") {
                        currentCategory = CleanCategory(name: "User App Cache", size: size, detail: extractCount(from: trimmed), icon: "archivebox", color: .blue)
                    } else if trimmed.contains("User app logs") {
                        currentCategory = CleanCategory(name: "User App Logs", size: size, detail: extractCount(from: trimmed), icon: "doc.text", color: .orange)
                    } else if trimmed.contains("Darwin user temp") {
                        currentCategory = CleanCategory(name: "Temp Files", size: size, detail: extractCount(from: trimmed), icon: "clock", color: .purple)
                    } else if trimmed.contains("Darwin user cache") {
                        currentCategory = CleanCategory(name: "System Cache", size: size, detail: extractCount(from: trimmed), icon: "internaldrive", color: .teal)
                    } else if trimmed.contains("Trash") {
                        currentCategory = CleanCategory(name: "Trash", size: trimmed.contains("empty") ? "--" : size, detail: trimmed.contains("empty") ? "Items to empty" : "", icon: "trash", color: .green)
                    } else if trimmed.contains("orphan") || trimmed.contains("Orphan") || trimmed.contains("bun cache") {
                        currentCategory = CleanCategory(name: "Orphan / Residual", size: size, detail: extractCount(from: trimmed), icon: "questionmark.folder", color: .red)
                    } else if trimmed.contains("Xcode") || trimmed.contains("DerivedData") {
                        currentCategory = CleanCategory(name: "Xcode Cache", size: size, detail: extractCount(from: trimmed), icon: "hammer", color: .blue)
                    } else if trimmed.contains("brew") || trimmed.contains("Homebrew") {
                        currentCategory = CleanCategory(name: "Homebrew Cache", size: size, detail: extractCount(from: trimmed), icon: "mug", color: .orange)
                    } else if trimmed.contains("Wallpaper") {
                        currentCategory = CleanCategory(name: "Wallpaper Cache", size: size, detail: "", icon: "photo", color: .indigo)
                    } else if trimmed.contains("Media analysis") {
                        currentCategory = CleanCategory(name: "Media Analysis Cache", size: size, detail: extractCount(from: trimmed), icon: "play.rectangle", color: .pink)
                    } else if trimmed.contains("App Store") {
                        currentCategory = CleanCategory(name: "App Store Cache", size: size, detail: extractCount(from: trimmed), icon: "app.badge", color: .blue)
                    } else {
                        // Generic category with size
                        let name = trimmed.replacingOccurrences(of: "→", with: "")
                            .components(separatedBy: CharacterSet(charactersIn: "0123456789.,")).first?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
                        currentCategory = CleanCategory(name: name, size: size, detail: "", icon: "folder", color: .secondary)
                    }
                }
                continue
            }

            // File details: [DRY-RUN] lines, Potential orphan lines, or paths starting with / or ~
            if trimmed.hasPrefix("[DRY-RUN]") {
                let path = trimmed.replacingOccurrences(of: "[DRY-RUN]", with: "")
                    .replacingOccurrences(of: "Would sudo remove:", with: "")
                    .replacingOccurrences(of: "Would remove:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { currentFiles.append(path) }
            } else if trimmed.contains("orphan dotfile:") || trimmed.contains("orphan:") {
                let path = trimmed.components(separatedBy: "orphan dotfile:").last?
                    .components(separatedBy: "orphan:").last?
                    .trimmingCharacters(in: .whitespaces) ?? trimmed
                if !path.isEmpty { currentFiles.append(path) }
            }
        }

        // Flush last category
        if var cat = currentCategory {
            cat.files = currentFiles
            categories.append(cat)
        }

        let structuredCategories = parseCleanListFile()
        if !structuredCategories.isEmpty {
            categories = structuredCategories
        }

        let totalBytes = categories.compactMap { parseSizeToBytes($0.size) }.reduce(0, +)
        cleanTotalSize = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        cleanCategories = categories
    }

    private func parseCleanListFile() -> [CleanCategory] {
        guard let text = try? String(contentsOf: runtime.cleanListFile, encoding: .utf8) else {
            return []
        }

        var categories: [CleanCategory] = []
        var currentSection = ""
        var currentTargets: [CleanTarget] = []

        func flushSection() {
            guard !currentSection.isEmpty, !currentTargets.isEmpty else { return }
            categories.append(makeCleanCategory(section: currentSection, targets: currentTargets))
            currentTargets = []
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("# Summary") { break }
            if line.hasPrefix("#") { continue }

            if line.hasPrefix("==="), line.hasSuffix("===") {
                flushSection()
                currentSection = line
                    .replacingOccurrences(of: "=", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            guard !currentSection.isEmpty else { continue }
            guard let markerRange = line.range(of: "  # ") ?? line.range(of: " # ") else { continue }

            let path = String(line[..<markerRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let metadata = String(line[markerRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }

            let size = extractSize(from: metadata) ?? "--"
            let sizeBytes = parseSizeToBytes(size)
            let itemCount = extractItemCount(from: metadata)
            let risk = classifyCleanTargetRisk(section: currentSection, path: path, sizeBytes: sizeBytes)

            currentTargets.append(
                CleanTarget(
                    path: path,
                    size: size,
                    sizeBytes: sizeBytes,
                    itemCount: itemCount,
                    risk: risk.level,
                    reason: risk.reason
                )
            )
        }

        flushSection()
        return categories
    }

    private func makeCleanCategory(section: String, targets: [CleanTarget]) -> CleanCategory {
        let totalBytes = targets.reduce(Int64(0)) { $0 + max($1.sizeBytes, 0) }
        let totalItems = targets.reduce(0) { $0 + max($1.itemCount, 1) }
        let highestRisk = targets.map(\.risk).max(by: { $0.severity < $1.severity }) ?? .low
        let presentation = cleanCategoryPresentation(for: section)
        let size = totalBytes > 0
            ? ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            : "--"

        return CleanCategory(
            name: section,
            size: size,
            detail: "\(targets.count) locations, \(totalItems) items",
            icon: presentation.icon,
            color: presentation.color,
            risk: highestRisk,
            riskReason: cleanCategoryRiskReason(section: section, targets: targets, highestRisk: highestRisk),
            targets: targets,
            files: targets.map(\.path)
        )
    }

    private func cleanCategoryPresentation(for section: String) -> (icon: String, color: Color) {
        let lower = section.lowercased()
        if lower.contains("user essentials") { return ("archivebox", .blue) }
        if lower.contains("app caches") { return ("internaldrive", .teal) }
        if lower.contains("browser") { return ("globe", .orange) }
        if lower.contains("cloud") || lower.contains("office") { return ("cloud", .cyan) }
        if lower.contains("developer") { return ("hammer", .blue) }
        if lower.contains("application support") { return ("folder.badge.gearshape", .purple) }
        if lower.contains("application") { return ("app", .indigo) }
        if lower.contains("virtualization") { return ("shippingbox", .orange) }
        if lower.contains("leftover") { return ("questionmark.folder", .red) }
        if lower.contains("backup") || lower.contains("firmware") { return ("externaldrive.badge.timemachine", .red) }
        if lower.contains("time machine") { return ("clock.arrow.circlepath", .red) }
        if lower.contains("large") { return ("doc.badge.ellipsis", .orange) }
        if lower.contains("system") { return ("gearshape", .red) }
        if lower.contains("project") { return ("folder.badge.gearshape", .blue) }
        return ("folder", .secondary)
    }

    private func cleanCategoryRiskReason(section: String, targets: [CleanTarget], highestRisk: CleanRiskLevel) -> String {
        let matching = targets.filter { $0.risk == highestRisk }
        let count = matching.count
        let reason = matching.first?.reason ?? highestRisk.explanation
        if count <= 1 {
            return reason
        }
        return "\(count) \(highestRisk.title.lowercased()) risk locations. \(reason)"
    }

    private func classifyCleanTargetRisk(section: String, path: String, sizeBytes: Int64) -> (level: CleanRiskLevel, reason: String) {
        let lowerSection = section.lowercased()
        let lowerPath = path.lowercased()
        let isLarge = sizeBytes >= Int64(1024 * 1024 * 1024)

        if lowerSection.contains("trash") || lowerPath.contains("/.trash") || lowerPath.contains("/trash") {
            return (.high, "Trash cleanup can permanently remove items the user may still expect to recover.")
        }

        if lowerSection.contains("system") || path.hasPrefix("/Library") || path.hasPrefix("/System") {
            return (.high, "System or admin-scoped path; review before deleting.")
        }

        if lowerSection.contains("backup") || lowerSection.contains("firmware") || lowerSection.contains("time machine") ||
            lowerPath.contains("mobilesync/backup") || lowerPath.contains("backup") || lowerPath.contains(".ipsw") {
            return (.high, "Backup or firmware data; deleting may remove restore points or require re-download.")
        }

        if lowerSection.contains("leftover") || lowerPath.contains("/launchagents") || lowerPath.contains("/launchdaemons") ||
            lowerPath.contains("/preferences/") {
            return (.high, "Residual app state or settings; verify the app is no longer needed.")
        }

        if lowerSection.contains("developer") || lowerPath.contains("/node_modules") || lowerPath.contains("/.dart_tool") ||
            lowerPath.contains("/build") || lowerPath.contains("/.next/cache") || lowerPath.contains("/deriveddata") {
            return (.medium, "Developer cache or build output; safe to regenerate but may trigger rebuilds or downloads.")
        }

        if lowerSection.contains("browser") {
            return (.medium, "Browser cache; pages may re-download assets, but cookies and profiles are not targeted.")
        }

        if lowerSection.contains("cloud") || lowerSection.contains("office") {
            return (.medium, "Cloud or office cache; apps may need to re-sync or rebuild local previews.")
        }

        if lowerSection.contains("application support") {
            return (.medium, "Application Support cache/log path; app state should be reviewed if the app is important.")
        }

        if lowerSection.contains("virtualization") {
            return (.medium, "Virtualization cache; virtual machines may re-download or rebuild helper files.")
        }

        if isLarge {
            return (.medium, "Large cleanup target; review the path before deleting.")
        }

        if lowerPath.contains("cache") || lowerPath.contains("/logs") || lowerPath.contains("/tmp") ||
            lowerPath.contains("__pycache__") || lowerPath.hasSuffix(".log") {
            return (.low, "Regenerable cache, log, or temporary file.")
        }

        return (.medium, "Review the path before deleting; Mole classified it as cleanup data.")
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

    private func extractItemCount(from line: String) -> Int {
        let pattern = #"(\d+)\s*items?"#
        guard let range = line.range(of: pattern, options: .regularExpression),
              let value = Int(line[range].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) else {
            return 1
        }
        return max(value, 1)
    }

    private func parseSizeToBytes(_ size: String) -> Int64 {
        let pattern = #"(\d+\.?\d*)\s*([KMGT]?B)"#
        guard let match = size.range(of: pattern, options: .regularExpression) else { return 0 }
        let normalized = String(size[match])
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        let numberPart = normalized.prefix { $0.isNumber || $0 == "." }
        let unit = String(normalized.dropFirst(numberPart.count))
        guard let value = Double(numberPart) else { return 0 }
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
                latestVersion = ""
                updateDownloadURL = ""
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

            // Download with progress using delegate + continuation
            let zipLocation: URL = try await withCheckedThrowingContinuation { continuation in
                let delegate = UpdateDownloadDelegate { [weak self] percent in
                    Task { @MainActor in
                        self?.updateDownloadPercent = percent
                        self?.updateProgress = "Downloading... \(Int(percent * 100))%"
                    }
                } onComplete: { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: NSError(domain: "Update", code: -1))
                    }
                }
                let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
                session.downloadTask(with: URL(string: updateDownloadURL)!).resume()
            }

            updateProgress = "Download complete"
            // zipLocation is already safely moved by the delegate
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
            let myPID = ProcessInfo.processInfo.processIdentifier

            // Write a shell script that waits for this process to exit, then replaces and relaunches
            let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Mole-relink.sh")
            let script = """
            #!/bin/bash
            # Wait for the old Mole process to exit
            while kill -0 \(myPID) 2>/dev/null; do
                sleep 0.3
            done
            sleep 0.5
            # Trash old app
            mv "\(currentApp.path)" "$HOME/.Trash/\(currentAppName).$(date +%s)" 2>/dev/null
            # Copy new app
            cp -R "\(newApp.path)" "\(newAppDest.path)"
            # Remove quarantine
            /usr/bin/xattr -cr "\(newAppDest.path)"
            # Cleanup temp files
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

            // Use nohup to fully detach the script from this process
            let runner = Process()
            runner.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            runner.arguments = ["/bin/bash", scriptURL.path]
            runner.standardOutput = FileHandle.nullDevice
            runner.standardError = FileHandle.nullDevice
            try runner.run()

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

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    let onComplete: (URL?, Error?) -> Void
    private var resumeCalled = false

    init(onProgress: @escaping (Double) -> Void, onComplete: @escaping (URL?, Error?) -> Void) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temp file is deleted after this method returns, so move it immediately
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Mole-update.tmp")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            onComplete(dest, nil)
        } catch {
            onComplete(nil, error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onComplete(nil, error) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }
}
