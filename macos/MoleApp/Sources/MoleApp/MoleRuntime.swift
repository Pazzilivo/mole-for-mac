import Foundation
import SwiftUI

enum MoleRuntimeError: LocalizedError {
    case missingRuntime(URL)
    case missingExecutable(URL)

    var errorDescription: String? {
        switch self {
        case let .missingRuntime(url):
            return "Bundled Mole runtime was not found at \(url.path)."
        case let .missingExecutable(url):
            return "Executable was not found at \(url.path)."
        }
    }
}

final class MoleRuntime {
    let root: URL

    init(resourceRoot: URL? = Bundle.main.resourceURL) {
        self.root = (resourceRoot ?? URL(fileURLWithPath: "."))
            .appendingPathComponent("MoleRuntime", isDirectory: true)
    }

    var moExecutable: URL {
        root.appendingPathComponent("mo")
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
    }

    func runtimeChecks() -> [RuntimeCheck] {
        [
            RuntimeCheck(
                title: "Native Swift engine",
                detail: "SystemMonitor, DiskAnalyzer, CleanEngine, UninstallEngine, OptimizeEngine",
                isAvailable: true
            ),
            RuntimeCheck(
                title: "CLI wrapper",
                detail: moExecutable.path,
                isAvailable: FileManager.default.isExecutableFile(atPath: moExecutable.path)
            )
        ]
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
            let monitor = SystemMonitor()
            let metrics = try await monitor.collect()
            status = StatusAdapter.convert(metrics)
            statusState = .ready
            append("Status refreshed", detail: "System metrics collected natively.")
        } catch {
            statusState = .failed(error.localizedDescription)
            append("Status unavailable", detail: error.localizedDescription, isError: true)
        }
    }

    func refreshApps() async {
        appsState = .loading
        do {
            let engine = UninstallEngine()
            let discovered = try await engine.listApps()
            apps = AppListAdapter.convert(discovered)
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
        do {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            analyzeProgress = "Scanning \(home)..."
            let scanner = DiskScanner()
            let scanResult = try await scanner.scan(path: home)
            analysis = AnalysisAdapter.convert(scanResult, path: home)
            analyzeState = .ready
            append("Home analyzed", detail: "Disk scan finished for \(home).")
        } catch {
            analyzeState = .failed(error.localizedDescription)
            append("Disk analysis failed", detail: error.localizedDescription, isError: true)
        }
    }

    func uninstallApp(_ app: AppEntry) async {
        let appName = app.uninstallName ?? app.name
        uninstallState = .loading
        uninstallProgress = "Uninstalling \(appName)..."
        do {
            let engine = UninstallEngine()
            let apps = try await engine.listApps()
            guard let matched = apps.first(where: { $0.id == app.bundleID || $0.name == appName }) else {
                uninstallState = .failed("App not found: \(appName)")
                uninstallProgress = ""
                append("Uninstall failed", detail: "App not found: \(appName)", isError: true)
                return
            }

            let residuals = try await engine.findResidualFiles(bundleId: matched.id, appName: matched.name)
            uninstallProgress = "Removing app and residuals..."
            let _ = try await engine.uninstallApp(matched, residuals: residuals)

            uninstallState = .idle
            uninstallProgress = ""
            append("Uninstalled \(appName)", detail: "App and leftovers moved to Trash.")
            await refreshApps()
        } catch {
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

        do {
            cleanProgress = "Scanning caches..."
            let cacheCleaner = AppCacheCleaner()
            let results = cacheCleaner.cleanAllAppCaches(dryRun: true)

            cleanProgress = ""
            let categories = CleanAdapter.convertCacheResults(results)
            let totalBytes = categories.compactMap { parseSizeToBytes($0.size) }.reduce(0, +)
            cleanTotalSize = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
            cleanCategories = categories
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
        do {
            let cacheCleaner = AppCacheCleaner()
            let _ = cacheCleaner.cleanAllAppCaches(dryRun: false)
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
            let monitor = SystemMonitor()
            let metrics = try await monitor.collect()

            let memoryUsedGB = Double(metrics.memory.used) / 1_073_741_824.0
            let memoryTotalGB = Double(metrics.memory.total) / 1_073_741_824.0
            let mainDisk = metrics.disks.first(where: { !$0.external }) ?? metrics.disks.first
            let diskUsedGB = Double(mainDisk?.used ?? 0) / 1_073_741_824.0
            let diskTotalGB = Double(mainDisk?.total ?? 0) / 1_073_741_824.0
            let diskUsedPercent = mainDisk?.usedPercent ?? 0.0
            let uptimeDays = Double(metrics.uptimeSeconds) / 86400.0

            optimizePlan = OptimizeAdapter.buildPlan(
                memoryUsedGB: memoryUsedGB,
                memoryTotalGB: memoryTotalGB,
                diskUsedGB: diskUsedGB,
                diskTotalGB: diskTotalGB,
                diskUsedPercent: diskUsedPercent,
                uptimeDays: uptimeDays
            )
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
