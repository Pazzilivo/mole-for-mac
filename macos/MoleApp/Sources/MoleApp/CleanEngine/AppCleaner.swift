import Foundation

/// Handles application data cleanup and orphan detection
/// Ported from lib/clean/apps.sh
class AppCleaner {

    private let fileManager = FileManager.default
    private let homeDir: URL
    private let maxDSStoreFiles = 10000

    // Orphan detection thresholds
    private let orphanAgeThreshold: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let claudeVMOrphanAgeThreshold: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    // Sensitive data patterns that should never be treated as orphaned
    private let orphanNeverDeletePatterns = [
        "*1password*", "*1Password*",
        "*keychain*", "*Keychain*",
        "*bitwarden*", "*Bitwarden*",
        "*lastpass*", "*LastPass*",
        "*keepass*", "*KeePass*",
        "*dashlane*", "*Dashlane*",
        "*enpass*", "*Enpass*",
        "*ssh*", "*gpg*", "*gnupg*",
        "com.apple.keychain*"
    ]

    init() {
        self.homeDir = fileManager.homeDirectoryForCurrentUser
    }

    // MARK: - .DS_Store Cleaning

    struct DSCleanResult {
        let fileCount: Int
        let totalSize: Int64
        let filesCleaned: [String]
    }

    func cleanDSStoreTree(dryRun: Bool = false) -> DSCleanResult {
        var filesCleaned: [String] = []
        var totalSize: Int64 = 0

        // Paths to exclude from .DS_Store cleaning
        let excludePaths = [
            "Library/Application Support/MobileSync",
            "Library/Developer",
            ".Trash",
            "node_modules",
            ".git",
            "Library/Caches"
        ]

        func shouldExclude(_ path: String) -> Bool {
            for exclude in excludePaths {
                if path.contains(exclude) {
                    return true
                }
            }
            return false
        }

        func findDSStoreFiles(in directory: URL, maxDepth: Int = 5) -> [URL] {
            var dsStoreFiles: [URL] = []

            guard maxDepth > 0 else { return dsStoreFiles }
            guard !shouldExclude(directory.path) else { return dsStoreFiles }

            do {
                let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)

                for item in contents {
                    if item.lastPathComponent == ".DS_Store" {
                        dsStoreFiles.append(item)
                    } else if item.hasDirectoryPath {
                        let subFiles = findDSStoreFiles(in: item, maxDepth: maxDepth - 1)
                        dsStoreFiles.append(contentsOf: subFiles)
                    }
                }
            } catch {
                // Ignore permission errors and continue
            }

            return dsStoreFiles
        }

        let dsStoreFiles = findDSStoreFiles(in: homeDir, maxDepth: 5)

        for file in dsStoreFiles.prefix(maxDSStoreFiles) {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: file.path)
                if let fileSize = attributes[.size] as? Int64 {
                    totalSize += fileSize
                }

                if !dryRun {
                    try fileManager.removeItem(at: file)
                }

                filesCleaned.append(file.path)
            } catch {
                print("Failed to remove .DS_Store file: \(file.path)")
            }
        }

        return DSCleanResult(
            fileCount: filesCleaned.count,
            totalSize: totalSize,
            filesCleaned: filesCleaned
        )
    }

    // MARK: - Installed Apps Scanning

    struct InstalledAppsResult {
        let bundleIDs: Set<String>
        let runningApps: Set<String>
        let launchAgents: Set<String>
        let scanTime: Date
    }

    func scanInstalledApps() -> InstalledAppsResult {
        var bundleIDs = Set<String>()
        var runningApps = Set<String>()
        var launchAgents = Set<String>()

        // Define application directories
        let appDirectories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            homeDir.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/opt/homebrew/Caskroom"),
            URL(fileURLWithPath: "/usr/local/Caskroom"),
            homeDir.appendingPathComponent("Library/Application Support/Setapp/Applications")
        ]

        // Scan for installed applications
        for appDir in appDirectories {
            guard fileManager.fileExists(atPath: appDir.path) else { continue }

            if let enumerator = fileManager.enumerator(at: appDir, includingPropertiesForKeys: nil) {
                for case let appURL as URL in enumerator {
                    if appURL.pathExtension == "app" {
                        if let bundleID = getBundleID(for: appURL) {
                            bundleIDs.insert(bundleID)
                        }
                    }
                }
            }
        }

        // Get running apps
        runningApps = getRunningApps()

        // Get LaunchAgents
        launchAgents = getLaunchAgents()

        return InstalledAppsResult(
            bundleIDs: bundleIDs,
            runningApps: runningApps,
            launchAgents: launchAgents,
            scanTime: Date()
        )
    }

    private func getBundleID(for appURL: URL) -> String? {
        let plistPath = appURL.appendingPathComponent("Contents/Info.plist")

        guard fileManager.fileExists(atPath: plistPath.path) else {
            return nil
        }

        // Use PlistBuddy to read the bundle identifier
        let task = Process()
        task.launchPath = "/usr/libexec/PlistBuddy"
        task.arguments = ["-c", "Print :CFBundleIdentifier", plistPath.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0,
               let data = try pipe.fileHandleForReading.readToEnd(),
               let bundleID = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return bundleID
            }
        } catch {
            print("Failed to read bundle ID for \(appURL.path): \(error.localizedDescription)")
        }

        return nil
    }

    private func getRunningApps() -> Set<String> {
        var runningApps = Set<String>()

        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "tell application \"System Events\" to get bundle identifier of every application process"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0,
               let data = try pipe.fileHandleForReading.readToEnd(),
               let output = String(data: data, encoding: .utf8) {
                // Parse comma-separated bundle IDs
                let bundleIDs = output.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                for bundleID in bundleIDs {
                    if !bundleID.isEmpty && bundleID != "missing value" {
                        runningApps.insert(bundleID)
                    }
                }
            }
        } catch {
            print("Failed to get running apps: \(error.localizedDescription)")
        }

        return runningApps
    }

    private func getLaunchAgents() -> Set<String> {
        var launchAgents = Set<String>()

        let launchAgentPaths = [
            homeDir.appendingPathComponent("Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents")
        ]

        for launchAgentPath in launchAgentPaths {
            guard fileManager.fileExists(atPath: launchAgentPath.path) else { continue }

            do {
                let contents = try fileManager.contentsOfDirectory(at: launchAgentPath, includingPropertiesForKeys: nil)
                for item in contents {
                    if item.pathExtension == "plist" {
                        let agentName = item.deletingPathExtension().lastPathComponent
                        launchAgents.insert(agentName)
                    }
                }
            } catch {
                print("Failed to list LaunchAgents: \(error.localizedDescription)")
            }
        }

        return launchAgents
    }

    // MARK: - Orphan Detection

    struct OrphanResult {
        let bundleID: String
        let path: String
        let type: OrphanType
        let sizeBytes: Int64
        let lastModified: Date
    }

    enum OrphanType {
        case cache
        case logs
        case savedState
        case launchAgent
        case preferences
        case applicationSupport
    }

    func isBundleOrphaned(bundleID: String, path: String, installedApps: InstalledAppsResult) -> Bool {
        // Check against sensitive data patterns
        for pattern in orphanNeverDeletePatterns {
            if bundleID.lowercased().contains(pattern.lowercased().replacingOccurrences(of: "*", with: "")) {
                return false
            }
        }

        // Check if app is still installed
        if installedApps.bundleIDs.contains(bundleID) {
            return false
        }

        // Check if app is currently running
        if installedApps.runningApps.contains(bundleID) {
            return false
        }

        // Check for hardcoded system components
        let systemComponents = [
            "loginwindow", "dock", "systempreferences", "systemsettings",
            "settings", "controlcenter", "finder", "safari"
        ]

        if systemComponents.contains(bundleID.lowercased()) {
            return false
        }

        // Check file modification time
        if let attributes = try? fileManager.attributesOfItem(atPath: path),
           let modificationDate = attributes[.modificationDate] as? Date {
            let daysSinceModified = Date().timeIntervalSince(modificationDate)
            if daysSinceModified < orphanAgeThreshold {
                return false
            }
        }

        return true
    }

    func isClaudeVMBundleOrphaned(vmBundlePath: String, installedApps: InstalledAppsResult) -> Bool {
        guard fileManager.fileExists(atPath: vmBundlePath) else {
            return false
        }

        // Extra guard: check if Claude is running
        if isProcessRunning("Claude") {
            return false
        }

        let claudeBundleID = "com.anthropic.claudefordesktop"

        // Check if Claude Desktop is installed
        if installedApps.bundleIDs.contains(claudeBundleID) {
            return false
        }

        // Check modification time
        if let attributes = try? fileManager.attributesOfItem(atPath: vmBundlePath),
           let modificationDate = attributes[.modificationDate] as? Date {
            let daysSinceModified = Date().timeIntervalSince(modificationDate)
            if daysSinceModified < claudeVMOrphanAgeThreshold {
                return false
            }
        }

        return true
    }

    // MARK: - Orphaned App Data Cleanup

    func cleanOrphanedAppData(dryRun: Bool = false) -> [OrphanResult] {
        var orphanResults: [OrphanResult] = []

        let installedApps = scanInstalledApps()

        // Resource types to scan
        let resourceTypes: [(path: String, type: OrphanType)] = [
            ("Library/Caches", .cache),
            ("Library/Logs", .logs),
            ("Library/Saved Application State", .savedState)
        ]

        for (resourcePath, type) in resourceTypes {
            let fullPath = homeDir.appendingPathComponent(resourcePath)

            guard fileManager.fileExists(atPath: fullPath.path) else {
                continue
            }

            do {
                let contents = try fileManager.contentsOfDirectory(at: fullPath, includingPropertiesForKeys: nil)

                for item in contents {
                    let bundleID = item.lastPathComponent.replacingOccurrences(of: ".savedState", with: "")

                    if isBundleOrphaned(bundleID: bundleID, path: item.path, installedApps: installedApps) {
                        let size = getDirectorySize(item)

                        if !dryRun {
                            try? fileManager.removeItem(at: item)
                        }

                        orphanResults.append(OrphanResult(
                            bundleID: bundleID,
                            path: item.path,
                            type: type,
                            sizeBytes: size,
                            lastModified: (try? fileManager.attributesOfItem(atPath: item.path))?[.modificationDate] as? Date ?? Date()
                        ))
                    }
                }
            } catch {
                print("Failed to scan \(resourcePath): \(error.localizedDescription)")
            }
        }

        // Handle Claude VM bundles
        let claudeSupportDir = homeDir.appendingPathComponent("Library/Application Support/Claude")
        if fileManager.fileExists(atPath: claudeSupportDir.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(at: claudeSupportDir, includingPropertiesForKeys: nil)

                for item in contents {
                    if item.pathExtension == "bundle" {
                        if isClaudeVMBundleOrphaned(vmBundlePath: item.path, installedApps: installedApps) {
                            let size = getDirectorySize(item)

                            if !dryRun {
                                try? fileManager.removeItem(at: item)
                            }

                            orphanResults.append(OrphanResult(
                                bundleID: "com.anthropic.claude.vm",
                                path: item.path,
                                type: .applicationSupport,
                                sizeBytes: size,
                                lastModified: (try? fileManager.attributesOfItem(atPath: item.path))?[.modificationDate] as? Date ?? Date()
                            ))
                        }
                    }
                }
            } catch {
                print("Failed to scan Claude VM bundles: \(error.localizedDescription)")
            }
        }

        return orphanResults
    }

    // MARK: - Orphaned System Services Cleanup

    func cleanOrphanedSystemServices(dryRun: Bool = false) -> [OrphanResult] {
        var orphanResults: [OrphanResult] = []

        // This requires sudo access
        guard hasSudoAccess() else {
            print("Skipping system services cleanup - no sudo access")
            return orphanResults
        }

        let installedApps = scanInstalledApps()

        // Scan system LaunchDaemons and LaunchAgents
        let systemPaths = [
            ("/Library/LaunchDaemons", true),
            ("/Library/LaunchAgents", false),
            ("/Library/PrivilegedHelperTools", false)
        ]

        for (systemPath, requiresUnload) in systemPaths {
            let systemURL = URL(fileURLWithPath: systemPath)

            guard fileManager.fileExists(atPath: systemURL.path) else {
                continue
            }

            do {
                let contents = try fileManager.contentsOfDirectory(at: systemURL, includingPropertiesForKeys: nil)

                for item in contents {
                    guard item.pathExtension == "plist" || item.pathExtension.isEmpty else {
                        continue
                    }

                    let bundleID = item.deletingPathExtension().lastPathComponent

                    // Skip Apple system files
                    if bundleID.hasPrefix("com.apple.") {
                        continue
                    }

                    if isSystemServiceOrphaned(bundleID: bundleID, itemPath: item, installedApps: installedApps) {
                        let size = getDirectorySize(item)

                        if !dryRun {
                            // Unload LaunchDaemon/LaunchAgent if needed
                            if requiresUnload {
                                unloadService(at: item)
                            }

                            // Remove the file
                            try? fileManager.removeItem(at: item)
                        }

                        orphanResults.append(OrphanResult(
                            bundleID: bundleID,
                            path: item.path,
                            type: item.pathExtension == "plist" ? .launchAgent : .applicationSupport,
                            sizeBytes: size,
                            lastModified: (try? fileManager.attributesOfItem(atPath: item.path))?[.modificationDate] as? Date ?? Date()
                        ))
                    }
                }
            } catch {
                print("Failed to scan \(systemPath): \(error.localizedDescription)")
            }
        }

        return orphanResults
    }

    private func isSystemServiceOrphaned(bundleID: String, itemPath: URL, installedApps: InstalledAppsResult) -> Bool {
        // Read the binary path from the plist
        guard let binaryPath = getBinaryPathFromPlist(itemPath) else {
            return false
        }

        // Check if the binary still exists
        guard !fileManager.fileExists(atPath: binaryPath) else {
            return false
        }

        // Check if the binary is in a package-manager or system directory
        let packageManagedPaths = [
            "/usr/local/bin", "/usr/local/sbin",
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/bin", "/usr/sbin", "/bin", "/sbin",
            "/usr/libexec"
        ]

        for systemPath in packageManagedPaths {
            if binaryPath.hasPrefix(systemPath) {
                return false
            }
        }

        // Check if the app is still installed
        if installedApps.bundleIDs.contains(bundleID) {
            return false
        }

        return true
    }

    private func getBinaryPathFromPlist(_ plistURL: URL) -> String? {
        let task = Process()
        task.launchPath = "/usr/libexec/PlistBuddy"
        task.arguments = ["-c", "Print :ProgramArguments:0", plistURL.path]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0,
               let data = try pipe.fileHandleForReading.readToEnd(),
               let binaryPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return binaryPath
            }
        } catch {
            // Try Program key instead with new Process object
            let task2 = Process()
            task2.launchPath = "/usr/libexec/PlistBuddy"
            task2.arguments = ["-c", "Print :Program", plistURL.path]

            let pipe2 = Pipe()
            task2.standardOutput = pipe2
            task2.standardError = Pipe()

            do {
                try task2.run()
                task2.waitUntilExit()

                if task2.terminationStatus == 0,
                   let data = try pipe2.fileHandleForReading.readToEnd(),
                   let binaryPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    return binaryPath
                }
            } catch {
                return nil
            }
        }

        return nil
    }

    private func unloadService(at plistURL: URL) {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["unload", plistURL.path]

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("Failed to unload service at \(plistURL.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Orphaned Container Stubs Cleanup

    func cleanOrphanedContainerStubs(dryRun: Bool = false) -> [OrphanResult] {
        var orphanResults: [OrphanResult] = []

        let containersDir = homeDir.appendingPathComponent("Library/Containers")
        guard fileManager.fileExists(atPath: containersDir.path) else {
            return orphanResults
        }

        // Known stub patterns: bundle_id_glob -> app_path_to_check
        let stubPatterns: [String: String] = [
            "com.macpaw.CleanMyMac*": "/Applications/CleanMyMac X.app",
            "*.com.macpaw.CleanMyMac*": "/Applications/CleanMyMac X.app"
        ]

        let installedApps = scanInstalledApps()

        do {
            let contents = try fileManager.contentsOfDirectory(at: containersDir, includingPropertiesForKeys: nil)

            for container in contents {
                let bundleID = container.lastPathComponent

                // Check if this is a stub-only container
                guard isStubOnlyContainer(at: container) else {
                    continue
                }

                // Check against known stub patterns
                var isOrphaned = false
                for (pattern, appPath) in stubPatterns {
                    if bundleID.matchesGlob(pattern: pattern) {
                        if !fileManager.fileExists(atPath: appPath) {
                            isOrphaned = true
                            break
                        }
                    }
                }

                // Generic check if the app is no longer installed
                if !isOrphaned && !installedApps.bundleIDs.contains(bundleID) {
                    isOrphaned = true
                }

                if isOrphaned {
                    let size = getDirectorySize(container)

                    if !dryRun {
                        try? fileManager.removeItem(at: container)
                    }

                    orphanResults.append(OrphanResult(
                        bundleID: bundleID,
                        path: container.path,
                        type: .applicationSupport,
                        sizeBytes: size,
                        lastModified: (try? fileManager.attributesOfItem(atPath: container.path))?[.modificationDate] as? Date ?? Date()
                    ))
                }
            }
        } catch {
            print("Failed to scan container stubs: \(error.localizedDescription)")
        }

        return orphanResults
    }

    private func isStubOnlyContainer(at url: URL) -> Bool {
        let metadataPlist = url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")

        guard fileManager.fileExists(atPath: metadataPlist.path) else {
            return false
        }

        // Check if there are any other files besides the metadata plist
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)

            for item in contents {
                if item.lastPathComponent != ".com.apple.containermanagerd.metadata.plist" {
                    return false
                }
            }

            return true
        } catch {
            return false
        }
    }

    // MARK: - Helper Functions

    private func getDirectorySize(_ url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }

        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    if let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                } catch {
                    continue
                }
            }
        }

        return totalSize
    }

    private func isProcessRunning(_ processName: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-x", processName]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func hasSudoAccess() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/sudo"
        task.arguments = ["-n", "true"]

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - String Pattern Matching Extension

internal extension String {
    func matchesGlob(pattern: String) -> Bool {
        // Convert shell-style glob pattern to regex
        var regexPattern = pattern
        regexPattern = regexPattern.replacingOccurrences(of: ".", with: "\\.")
        regexPattern = regexPattern.replacingOccurrences(of: "*", with: ".*")
        regexPattern = "^\(regexPattern)$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }

        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, range: range) != nil
    }
}