import Foundation

/// Handles application cache cleaning for macOS apps
/// Ported from lib/clean/app_caches.sh
class AppCacheCleaner {

    private let fileManager = FileManager.default
    private let homeDir: URL

    init() {
        self.homeDir = fileManager.homeDirectoryForCurrentUser
    }

    // MARK: - Cache Cleaning Results

    struct CacheResult {
        let categoryName: String
        let sizeBytes: Int64
        let itemCount: Int
        let items: [String]
    }

    // MARK: - Process Detection

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

    // MARK: - Directory Size Calculation

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

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Safe Directory Removal

    private func safeRemoveDirectory(at url: URL, dryRun: Bool = false) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }

        if dryRun {
            return true
        }

        do {
            // Remove directory contents, not the directory itself
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
                return false
            }

            var removedItems = 0
            for case let itemURL as URL in enumerator {
                do {
                    try fileManager.removeItem(at: itemURL)
                    removedItems += 1
                } catch {
                    print("Failed to remove \(itemURL.path): \(error.localizedDescription)")
                }
            }

            return removedItems > 0
        } catch {
            print("Failed to enumerate directory \(url.path): \(error.localizedDescription)")
            return false
        }
    }

    private func cleanDirectoryContents(at url: URL, dryRun: Bool = false) -> Int {
        guard fileManager.fileExists(atPath: url.path) else {
            return 0
        }

        var removedCount = 0

        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)

            for item in contents {
                if safeRemoveDirectory(at: item, dryRun: dryRun) {
                    removedCount += 1
                }
            }
        } catch {
            print("Failed to list contents of \(url.path): \(error.localizedDescription)")
        }

        return removedCount
    }

    // MARK: - Xcode Cache Cleaning

    func cleanXcodeDerivedData(dryRun: Bool = false) -> CacheResult? {
        // Skip while Xcode is running to avoid build failures
        if isProcessRunning("Xcode") {
            print("Xcode is running, skipping DerivedData cleanup")
            return nil
        }

        let derivedDataURL = homeDir.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard fileManager.fileExists(atPath: derivedDataURL.path) else {
            return nil
        }

        var itemsCleaned = 0
        var pathsRemoved: [String] = []

        do {
            let projects = try fileManager.contentsOfDirectory(at: derivedDataURL, includingPropertiesForKeys: nil)

            // Calculate size before removal
            var projectSizes: [String: Int64] = [:]
            for project in projects {
                projectSizes[project.path] = getDirectorySize(project)
            }

            // Remove items after size calculation
            for project in projects {
                if safeRemoveDirectory(at: project, dryRun: dryRun) {
                    itemsCleaned += 1
                    pathsRemoved.append(project.path)
                }
            }

            let totalSize = pathsRemoved.reduce(Int64(0)) { $0 + (projectSizes[$1] ?? 0) }

            return CacheResult(
                categoryName: "Xcode DerivedData",
                sizeBytes: totalSize,
                itemCount: itemsCleaned,
                items: pathsRemoved
            )
        } catch {
            print("Failed to scan DerivedData: \(error.localizedDescription)")
            return nil
        }
    }

    func cleanXcodeTools(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let xcodeRunning = isProcessRunning("Xcode")
        let simulatorRunning = isProcessRunning("Simulator")

        // Simulator caches (skip while Simulator is running)
        if !simulatorRunning {
            let simulatorCache = homeDir.appendingPathComponent("Library/Developer/CoreSimulator/Caches")
            let result = cleanDirectoryContents(at: simulatorCache, dryRun: dryRun)
            if result > 0 {
                results.append(CacheResult(
                    categoryName: "Simulator cache",
                    sizeBytes: getDirectorySize(simulatorCache),
                    itemCount: result,
                    items: [simulatorCache.path]
                ))
            }

            let simulatorTemp = homeDir.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
            if let enumerator = fileManager.enumerator(at: simulatorTemp, includingPropertiesForKeys: nil) {
                for case let deviceURL as URL in enumerator {
                    if deviceURL.lastPathComponent == "data" {
                        let tempDir = deviceURL.appendingPathComponent("tmp")
                        let result = cleanDirectoryContents(at: tempDir, dryRun: dryRun)
                        if result > 0 {
                            results.append(CacheResult(
                                categoryName: "Simulator temp files",
                                sizeBytes: getDirectorySize(tempDir),
                                itemCount: result,
                                items: [tempDir.path]
                            ))
                        }
                    }
                }
            }

            let coreSimulatorLogs = homeDir.appendingPathComponent("Library/Logs/CoreSimulator")
            let logsResult = cleanDirectoryContents(at: coreSimulatorLogs, dryRun: dryRun)
            if logsResult > 0 {
                results.append(CacheResult(
                    categoryName: "CoreSimulator logs",
                    sizeBytes: getDirectorySize(coreSimulatorLogs),
                    itemCount: logsResult,
                    items: [coreSimulatorLogs.path]
                ))
            }

            // Remove unavailable simulator devices
            removeUnavailableSimulatorDevices(dryRun: dryRun)
        }

        // Xcode-specific caches
        let xcodeCache = homeDir.appendingPathComponent("Library/Caches/com.apple.dt.Xcode")
        let xcodeCacheResult = cleanDirectoryContents(at: xcodeCache, dryRun: dryRun)
        if xcodeCacheResult > 0 {
            results.append(CacheResult(
                categoryName: "Xcode cache",
                sizeBytes: getDirectorySize(xcodeCache),
                itemCount: xcodeCacheResult,
                items: [xcodeCache.path]
            ))
        }

        let iOSDeviceLogs = homeDir.appendingPathComponent("Library/Developer/Xcode/iOS Device Logs")
        let iOSResult = cleanDirectoryContents(at: iOSDeviceLogs, dryRun: dryRun)
        if iOSResult > 0 {
            results.append(CacheResult(
                categoryName: "iOS device logs",
                sizeBytes: getDirectorySize(iOSDeviceLogs),
                itemCount: iOSResult,
                items: [iOSDeviceLogs.path]
            ))
        }

        let watchOSDeviceLogs = homeDir.appendingPathComponent("Library/Developer/Xcode/watchOS Device Logs")
        let watchResult = cleanDirectoryContents(at: watchOSDeviceLogs, dryRun: dryRun)
        if watchResult > 0 {
            results.append(CacheResult(
                categoryName: "watchOS device logs",
                sizeBytes: getDirectorySize(watchOSDeviceLogs),
                itemCount: watchResult,
                items: [watchOSDeviceLogs.path]
            ))
        }

        let productsDir = homeDir.appendingPathComponent("Library/Developer/Xcode/Products")
        let productsResult = cleanDirectoryContents(at: productsDir, dryRun: dryRun)
        if productsResult > 0 {
            results.append(CacheResult(
                categoryName: "Xcode build products",
                sizeBytes: getDirectorySize(productsDir),
                itemCount: productsResult,
                items: [productsDir.path]
            ))
        }

        if !xcodeRunning {
            // DerivedData and documentation
            if let derivedDataResult = cleanXcodeDerivedData(dryRun: dryRun) {
                results.append(derivedDataResult)
            }

            let documentationCache = homeDir.appendingPathComponent("Library/Developer/Xcode/DocumentationCache")
            let docResult = cleanDirectoryContents(at: documentationCache, dryRun: dryRun)
            if docResult > 0 {
                results.append(CacheResult(
                    categoryName: "Xcode documentation cache",
                    sizeBytes: getDirectorySize(documentationCache),
                    itemCount: docResult,
                    items: [documentationCache.path]
                ))
            }

            let documentationIndex = homeDir.appendingPathComponent("Library/Developer/Xcode/DocumentationIndex")
            let indexResult = cleanDirectoryContents(at: documentationIndex, dryRun: dryRun)
            if indexResult > 0 {
                results.append(CacheResult(
                    categoryName: "Xcode documentation index",
                    sizeBytes: getDirectorySize(documentationIndex),
                    itemCount: indexResult,
                    items: [documentationIndex.path]
                ))
            }
        }

        return results
    }

    private func removeUnavailableSimulatorDevices(dryRun: Bool = false) {
        let task = Process()
        task.launchPath = "/usr/bin/xcrun"
        task.arguments = ["simctl", "delete", "unavailable"]

        if dryRun {
            return
        }

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            print("Failed to remove unavailable simulators: \(error.localizedDescription)")
        }
    }

    // MARK: - Code Editor Cache Cleaning

    func cleanCodeEditors(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let codeEditorPaths = [
            ("VS Code logs", "Library/Application Support/Code/logs"),
            ("VS Code cache", "Library/Caches/Code"),
            ("VS Code extension cache", "Library/Application Support/Code/CachedExtensions"),
            ("VS Code data cache", "Library/Application Support/Code/CachedData"),
            ("Sublime Text cache", "Library/Caches/com.sublimetext.*"),
            ("Zed cache", "Library/Caches/Zed"),
            ("Zed logs", "Library/Logs/Zed"),
            ("Warp cache", "Library/Caches/dev.warp.Warp-Stable"),
            ("Warp log", "Library/Logs/warp.log"),
            ("Ghostty cache", "Library/Caches/com.mitchellh.ghostty")
        ]

        for (name, path) in codeEditorPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Communication Apps Cache Cleaning

    func cleanCommunicationApps(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let commPaths = [
            ("Discord cache", "Library/Application Support/discord/Cache"),
            ("Legcord cache", "Library/Application Support/legcord/Cache"),
            ("Slack cache", "Library/Application Support/Slack/Cache"),
            ("Zoom cache", "Library/Caches/us.zoom.xos"),
            ("WeChat cache", "Library/Caches/com.tencent.xinWeChat"),
            ("Telegram cache", "Library/Caches/ru.keepcoder.Telegram"),
            ("Microsoft Teams cache", "Library/Caches/com.microsoft.teams2"),
            ("WhatsApp cache", "Library/Caches/net.whatsapp.WhatsApp"),
            ("Skype cache", "Library/Caches/com.skype.skype"),
            ("Tencent Meeting cache", "Library/Caches/com.tencent.meeting"),
            ("WeCom cache", "Library/Caches/com.tencent.WeWorkMac"),
            ("Feishu cache", "Library/Caches/com.feishu.*")
        ]

        for (name, path) in commPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        // Microsoft Teams legacy cleanup
        let teamsLegacyPath = homeDir.appendingPathComponent("Library/Application Support/Microsoft/Teams")
        if fileManager.fileExists(atPath: teamsLegacyPath.path) {
            let teamsItems = [
                ("Cache", "Cache"),
                ("Application Cache", "Application Cache"),
                ("Code Cache", "Code Cache"),
                ("GPU Cache", "GPUCache"),
                ("logs", "logs"),
                ("tmp", "tmp")
            ]

            for (name, subpath) in teamsItems {
                let fullPath = teamsLegacyPath.appendingPathComponent(subpath)
                let result = cleanDirectoryContents(at: fullPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: "Microsoft Teams legacy \(name)",
                        sizeBytes: getDirectorySize(fullPath),
                        itemCount: result,
                        items: [fullPath.path]
                    ))
                }
            }
        }

        return results
    }

    // MARK: - DingTalk Cache Cleaning

    func cleanDingTalk(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let dingTalkPaths = [
            ("DingTalk cache", "Library/Caches/dd.work.exclusive4aliding"),
            ("AliLang security component", "Library/Caches/com.alibaba.AliLang.osx")
        ]

        for (name, path) in dingTalkPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        // DingTalk logs
        let iDingTalkPath = homeDir.appendingPathComponent("Library/Application Support/iDingTalk")
        if fileManager.fileExists(atPath: iDingTalkPath.path) {
            let logItems = ["log", "holmeslogs"]

            for logName in logItems {
                let logPath = iDingTalkPath.appendingPathComponent(logName)
                let result = cleanDirectoryContents(at: logPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: "DingTalk \(logName)",
                        sizeBytes: getDirectorySize(logPath),
                        itemCount: result,
                        items: [logPath.path]
                    ))
                }
            }
        }

        return results
    }

    // MARK: - AI Apps Cache Cleaning

    func cleanAIApps(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let aiAppPaths = [
            ("ChatGPT cache", "Library/Caches/com.openai.chat"),
            ("Claude desktop cache", "Library/Caches/com.anthropic.claudefordesktop"),
            ("Claude logs", "Library/Logs/Claude"),
            ("Codex CLI logs", "Library/Logs/com.openai.codex")
        ]

        for (name, path) in aiAppPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        // Codex (OpenAI, Electron)
        let codexPath = homeDir.appendingPathComponent("Library/Application Support/Codex")
        if fileManager.fileExists(atPath: codexPath.path) {
            let codexItems = [
                ("Cache", "Cache"),
                ("Code Cache", "Code Cache"),
                ("GPU Cache", "GPUCache"),
                ("Dawn Graphite Cache", "DawnGraphiteCache"),
                ("Dawn WebGPU Cache", "DawnWebGPUCache")
            ]

            for (name, subpath) in codexItems {
                let fullPath = codexPath.appendingPathComponent(subpath)
                let result = cleanDirectoryContents(at: fullPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: "Codex \(name)",
                        sizeBytes: getDirectorySize(fullPath),
                        itemCount: result,
                        items: [fullPath.path]
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Design Tools Cache Cleaning

    func cleanDesignTools(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let designPaths = [
            ("Sketch cache", "Library/Caches/com.bohemiancoding.sketch3"),
            ("Sketch app cache", "Library/Application Support/com.bohemiancoding.sketch3/cache"),
            ("Adobe cache", "Library/Caches/Adobe"),
            ("Adobe app caches", "Library/Caches/com.adobe.*"),
            ("Figma cache", "Library/Caches/com.figma.Desktop"),
            ("Adobe media cache files", "Library/Application Support/Adobe/Common/Media Cache Files")
        ]

        for (name, path) in designPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Final Cut Pro Cache Cleaning

    func cleanFinalCutPro(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        // Check if Final Cut Pro is running
        if isProcessRunning("Final Cut Pro") {
            print("Final Cut Pro is running, skipping cache cleanup")
            return results
        }

        let fcpCachePath = homeDir.appendingPathComponent("Library/Caches/com.apple.FinalCut")
        if fileManager.fileExists(atPath: fcpCachePath.path) {
            let result = cleanDirectoryContents(at: fcpCachePath, dryRun: dryRun)
            if result > 0 {
                results.append(CacheResult(
                    categoryName: "Final Cut Pro cache",
                    sizeBytes: getDirectorySize(fcpCachePath),
                    itemCount: result,
                    items: [fcpCachePath.path]
                ))
            }
        }

        // Clean Final Cut Pro generated caches
        let generatedCacheResults = cleanFinalCutProGeneratedCaches(dryRun: dryRun)
        results.append(contentsOf: generatedCacheResults)

        return results
    }

    private func cleanFinalCutProGeneratedCaches(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []
        let moviesDir = homeDir.appendingPathComponent("Movies")

        guard fileManager.fileExists(atPath: moviesDir.path) else {
            return results
        }

        // Find all .fcpbundle files
        do {
            let fcpBundles = try fileManager.contentsOfDirectory(at: moviesDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "fcpbundle" }

            for bundle in fcpBundles {
                let cacheResults = findFinalCutProCacheTargets(in: bundle, dryRun: dryRun)
                results.append(contentsOf: cacheResults)
            }
        } catch {
            print("Failed to scan Movies directory: \(error.localizedDescription)")
        }

        return results
    }

    private func findFinalCutProCacheTargets(in bundle: URL, dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        // Protected paths that should never be deleted
        let protectedPaths = [
            "Original Media",
            "CurrentVersion.flexolibrary",
            "CurrentVersion.plist",
            "Settings.plist",
            "Motion Templates",
            "Final Cut Pro Backups"
        ]

        // Cache targets that can be safely deleted
        let cacheTargets = [
            "Render Files/High Quality Media",
            "Transcoded Media/Proxy Media",
            "Analysis Files"
        ]

        for target in cacheTargets {
            let targetURL = bundle.appendingPathComponent(target)

            // Check if this is a protected path
            let isProtected = protectedPaths.contains { targetURL.path.contains($0) }
            if isProtected {
                continue
            }

            if fileManager.fileExists(atPath: targetURL.path) {
                if safeRemoveDirectory(at: targetURL, dryRun: dryRun) {
                    results.append(CacheResult(
                        categoryName: "Final Cut Pro generated cache",
                        sizeBytes: getDirectorySize(targetURL),
                        itemCount: 1,
                        items: [targetURL.path]
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Video Tools Cache Cleaning

    func cleanVideoTools(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let videoToolPaths = [
            ("ScreenFlow cache", "Library/Caches/net.telestream.screenflow10"),
            ("DaVinci Resolve cache", "Library/Caches/com.blackmagic-design.DaVinciResolve"),
            ("DaVinci Resolve CacheClip", "Movies/CacheClip"),
            ("Premiere Pro cache", "Library/Caches/com.adobe.PremierePro.*")
        ]

        for (name, path) in videoToolPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        // Add Final Cut Pro cleaning
        results.append(contentsOf: cleanFinalCutPro(dryRun: dryRun))

        return results
    }

    // MARK: - 3D Tools Cache Cleaning

    func clean3DTools(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let tool3DPaths = [
            ("Blender cache", "Library/Caches/org.blenderfoundation.blender"),
            ("Cinema 4D cache", "Library/Caches/com.maxon.cinema4d"),
            ("Autodesk cache", "Library/Caches/com.autodesk.*"),
            ("SketchUp cache", "Library/Caches/com.sketchup.*")
        ]

        for (name, path) in tool3DPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Main Cleaning Function

    func cleanAllAppCaches(dryRun: Bool = false) -> [CacheResult] {
        var allResults: [CacheResult] = []

        // Clean each category
        allResults.append(contentsOf: cleanXcodeTools(dryRun: dryRun))
        allResults.append(contentsOf: cleanCodeEditors(dryRun: dryRun))
        allResults.append(contentsOf: cleanCommunicationApps(dryRun: dryRun))
        allResults.append(contentsOf: cleanDingTalk(dryRun: dryRun))
        allResults.append(contentsOf: cleanAIApps(dryRun: dryRun))
        allResults.append(contentsOf: cleanDesignTools(dryRun: dryRun))
        allResults.append(contentsOf: cleanVideoTools(dryRun: dryRun))
        allResults.append(contentsOf: clean3DTools(dryRun: dryRun))
        allResults.append(contentsOf: cleanProductivityApps(dryRun: dryRun))
        allResults.append(contentsOf: cleanMediaPlayers(dryRun: dryRun))
        allResults.append(contentsOf: cleanVideoPlayers(dryRun: dryRun))
        allResults.append(contentsOf: cleanDownloadManagers(dryRun: dryRun))
        allResults.append(contentsOf: cleanGamingPlatforms(dryRun: dryRun))
        allResults.append(contentsOf: cleanTranslationApps(dryRun: dryRun))
        allResults.append(contentsOf: cleanScreenshotTools(dryRun: dryRun))
        allResults.append(contentsOf: cleanEmailClients(dryRun: dryRun))
        allResults.append(contentsOf: cleanTaskApps(dryRun: dryRun))
        allResults.append(contentsOf: cleanShellUtils(dryRun: dryRun))
        allResults.append(contentsOf: cleanSystemUtils(dryRun: dryRun))
        allResults.append(contentsOf: cleanNoteApps(dryRun: dryRun))
        allResults.append(contentsOf: cleanLauncherApps(dryRun: dryRun))
        allResults.append(contentsOf: cleanRemoteDesktop(dryRun: dryRun))

        return allResults
    }

    // MARK: - Additional App Categories

    func cleanProductivityApps(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let productivityPaths = [
            ("MiaoYan cache", "Library/Caches/com.tw93.MiaoYan"),
            ("Klee cache", "Library/Caches/com.klee.desktop"),
            ("Filo cache", "Library/Caches/com.filo.client"),
            ("Flomo cache", "Library/Caches/com.flomoapp.mac"),
            ("Quark video cache", "Library/Application Support/Quark/Cache/videoCache"),
            ("NetNewsWire cache", "Library/Containers/com.ranchero.NetNewsWire-Evergreen/Data/Library/Caches"),
            ("MindNode cache", "Library/Containers/com.ideasoncanvas.mindnode/Data/Library/Caches"),
            ("Kaku cache", ".cache/kaku")
        ]

        for (name, path) in productivityPaths {
            let expandedPath = path.hasPrefix("/") ? URL(fileURLWithPath: path) : homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanMediaPlayers(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        // Check Spotify for offline music
        let spotifyCache = homeDir.appendingPathComponent("Library/Caches/com.spotify.client")
        let spotifyData = homeDir.appendingPathComponent("Library/Application Support/Spotify")
        let offlineMusicPath = spotifyData.appendingPathComponent("PersistentCache/Storage/offline.bnk")

        var hasOfflineMusic = false
        if fileManager.fileExists(atPath: offlineMusicPath.path) {
            if let attributes = try? fileManager.attributesOfItem(atPath: offlineMusicPath.path),
               let fileSize = attributes[.size] as? UInt64, fileSize > 1024 {
                hasOfflineMusic = true
            }
        }

        if !hasOfflineMusic && fileManager.fileExists(atPath: spotifyCache.path) {
            let result = cleanDirectoryContents(at: spotifyCache, dryRun: dryRun)
            if result > 0 {
                results.append(CacheResult(
                    categoryName: "Spotify cache",
                    sizeBytes: getDirectorySize(spotifyCache),
                    itemCount: result,
                    items: [spotifyCache.path]
                ))
            }
        }

        let mediaPlayerPaths = [
            ("Apple Music cache", "Library/Caches/com.apple.Music"),
            ("Apple Podcasts cache", "Library/Caches/com.apple.podcasts"),
            ("Apple TV cache", "Library/Caches/com.apple.TV"),
            ("Plex cache", "Library/Caches/tv.plex.player.desktop"),
            ("NetEase Music cache", "Library/Caches/com.netease.163music"),
            ("QQ Music cache", "Library/Caches/com.tencent.QQMusic"),
            ("Kugou Music cache", "Library/Caches/com.kugou.mac"),
            ("Kuwo Music cache", "Library/Caches/com.kuwo.mac")
        ]

        for (name, path) in mediaPlayerPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanVideoPlayers(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let videoPlayerPaths = [
            ("IINA cache", "Library/Caches/com.colliderli.iina"),
            ("VLC cache", "Library/Caches/org.videolan.vlc"),
            ("MPV cache", "Library/Caches/io.mpv"),
            ("iQIYI cache", "Library/Caches/com.iqiyi.player"),
            ("Tencent Video cache", "Library/Caches/com.tencent.tenvideo"),
            ("Bilibili cache", "Library/Caches/tv.danmaku.bili"),
            ("Douyu cache", "Library/Caches/com.douyu.*"),
            ("Huya cache", "Library/Caches/com.huya.*"),
            ("Stremio cache", "Library/Caches/smart.stremio.*")
        ]

        for (name, path) in videoPlayerPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanDownloadManagers(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let downloadManagerPaths = [
            ("Aria2 cache", "Library/Caches/net.xmac.aria2gui"),
            ("Transmission cache", "Library/Caches/org.m0k.transmission"),
            ("qBittorrent cache", "Library/Caches/com.qbittorrent.qBittorrent"),
            ("Downie cache", "Library/Caches/com.downie.Downie-*"),
            ("Folx cache", "Library/Caches/com.folx.*"),
            ("Pacifist cache", "Library/Caches/com.charlessoft.pacifist.*")
        ]

        for (name, path) in downloadManagerPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanGamingPlatforms(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let gamingPaths = [
            ("Steam cache", "Library/Caches/com.valvesoftware.steam"),
            ("Epic Games cache", "Library/Caches/com.epicgames.EpicGamesLauncher"),
            ("Battle.net cache", "Library/Caches/com.blizzard.Battle.net"),
            ("EA Origin cache", "Library/Caches/com.ea.*"),
            ("GOG Galaxy cache", "Library/Caches/com.gog.galaxy"),
            ("Riot Games cache", "Library/Caches/com.riotgames.*")
        ]

        for (name, path) in gamingPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        // Minecraft specific paths
        let minecraftPath = homeDir.appendingPathComponent("Library/Application Support/minecraft")
        if fileManager.fileExists(atPath: minecraftPath.path) {
            let minecraftItems = [
                ("Minecraft logs", "logs"),
                ("Minecraft crash reports", "crash-reports"),
                ("Minecraft web cache", "webcache"),
                ("Minecraft web cache 2", "webcache2")
            ]

            for (name, subpath) in minecraftItems {
                let fullPath = minecraftPath.appendingPathComponent(subpath)
                let result = cleanDirectoryContents(at: fullPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(fullPath),
                        itemCount: result,
                        items: [fullPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanTranslationApps(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let translationPaths = [
            ("Youdao Dictionary cache", "Library/Caches/com.youdao.YoudaoDict"),
            ("Eudict cache", "Library/Caches/com.eudic.*"),
            ("Bob Translation cache", "Library/Caches/com.bob-build.Bob")
        ]

        for (name, path) in translationPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanScreenshotTools(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let screenshotPaths = [
            ("CleanShot cache", "Library/Caches/com.cleanshot.*"),
            ("Camo cache", "Library/Caches/com.reincubate.camo"),
            ("Xnip cache", "Library/Caches/com.xnipapp.xnip")
        ]

        for (name, path) in screenshotPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanEmailClients(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let emailPaths = [
            ("Spark cache", "Library/Caches/com.readdle.smartemail-Mac"),
            ("Airmail cache", "Library/Caches/com.airmail.*")
        ]

        for (name, path) in emailPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanTaskApps(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let taskPaths = [
            ("Todoist cache", "Library/Caches/com.todoist.mac.Todoist"),
            ("Any.do cache", "Library/Caches/com.any.do.*")
        ]

        for (name, path) in taskPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanShellUtils(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        // Remove individual shell utility files
        let shellFiles = [
            ("Zsh completion cache", ".zcompdump*"),
            ("Less history", ".lesshst"),
            ("Vim temporary files", ".viminfo.tmp"),
            ("wget HSTS cache", ".wget-hsts")
        ]

        for (name, pattern) in shellFiles {
            let expandedPath = homeDir.appendingPathComponent(pattern)
            if fileManager.fileExists(atPath: expandedPath.path) || expandedPath.path.contains("*") {
                // Handle wildcard patterns
                if pattern.contains("*") {
                    let directory = homeDir.appendingPathComponent(expandedPath.deletingLastPathComponent().path)
                    let wildcardPattern = expandedPath.lastPathComponent

                    if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
                        for case let fileURL as URL in enumerator {
                            if fileURL.lastPathComponent.matchesGlob(pattern: wildcardPattern) {
                                if safeRemoveDirectory(at: fileURL, dryRun: dryRun) {
                                    results.append(CacheResult(
                                        categoryName: name,
                                        sizeBytes: getDirectorySize(fileURL),
                                        itemCount: 1,
                                        items: [fileURL.path]
                                    ))
                                }
                            }
                        }
                    }
                } else {
                    if safeRemoveDirectory(at: expandedPath, dryRun: dryRun) {
                        results.append(CacheResult(
                            categoryName: name,
                            sizeBytes: getDirectorySize(expandedPath),
                            itemCount: 1,
                            items: [expandedPath.path]
                        ))
                    }
                }
            }
        }

        let shellPaths = [
            ("Cacher logs", ".cacher/logs"),
            ("Kite logs", ".kite/logs"),
            ("Warp cache", "Library/Caches/dev.warp.Warp-Stable"),
            ("Warp log", "Library/Logs/warp.log"),
            ("Ghostty cache", "Library/Caches/com.mitchellh.ghostty")
        ]

        for (name, path) in shellPaths {
            let expandedPath = path.hasPrefix("/") ? URL(fileURLWithPath: path) : homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanSystemUtils(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let systemUtilPaths = [
            ("Input Source Pro cache", "Library/Caches/com.runjuu.Input-Source-Pro"),
            ("WakaTime cache", "Library/Caches/macos-wakatime.WakaTime"),
            ("Stash cache", "Library/Caches/ws.stash.app.mac")
        ]

        for (name, path) in systemUtilPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        // WeType input method specific paths
        let weTypePath = homeDir.appendingPathComponent("Library/Application Support/WeType")
        if fileManager.fileExists(atPath: weTypePath.path) {
            let weTypeItems = [
                ("WeType image cache", "com.onevcat.Kingfisher.ImageCache.WeType"),
                ("WeType dict update cache", "DictUpdate")
            ]

            for (name, subpath) in weTypeItems {
                let fullPath = weTypePath.appendingPathComponent(subpath)
                let result = cleanDirectoryContents(at: fullPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(fullPath),
                        itemCount: result,
                        items: [fullPath.path]
                    ))
                }
            }
        }

        // mihomo-party proxy tool
        let mihomoPath = homeDir.appendingPathComponent("Library/Application Support/mihomo-party")
        if fileManager.fileExists(atPath: mihomoPath.path) {
            let mihomoItems = [
                ("mihomo-party cache", "Cache"),
                ("mihomo-party code cache", "Code Cache"),
                ("mihomo-party GPU cache", "GPUCache"),
                ("mihomo-party Dawn cache", "DawnGraphiteCache"),
                ("mihomo-party WebGPU cache", "DawnWebGPUCache"),
                ("mihomo-party logs", "logs")
            ]

            for (name, subpath) in mihomoItems {
                let fullPath = mihomoPath.appendingPathComponent(subpath)
                let result = cleanDirectoryContents(at: fullPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(fullPath),
                        itemCount: result,
                        items: [fullPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanNoteApps(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let notePaths = [
            ("Notion cache", "Library/Caches/notion.id"),
            ("Obsidian cache", "Library/Caches/md.obsidian"),
            ("Logseq cache", "Library/Caches/com.logseq.*"),
            ("Bear cache", "Library/Caches/com.bear-writer.*"),
            ("Evernote cache", "Library/Caches/com.evernote.*"),
            ("Yinxiang Note cache", "Library/Caches/com.yinxiang.*")
        ]

        for (name, path) in notePaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanLauncherApps(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let launcherPaths = [
            ("Alfred cache", "Library/Caches/com.runningwithcrayons.Alfred"),
            ("The Unarchiver cache", "Library/Caches/cx.c3.theunarchiver"),
            ("Raycast URL cache", "Library/Caches/com.raycast.macos/urlcache"),
            ("Raycast FS cache", "Library/Caches/com.raycast.macos/fsCachedData")
        ]

        for (name, path) in launcherPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    func cleanRemoteDesktop(dryRun: Bool = false) -> [CacheResult] {
        var results: [CacheResult] = []

        let remoteDesktopPaths = [
            ("TeamViewer cache", "Library/Caches/com.teamviewer.*"),
            ("AnyDesk cache", "Library/Caches/com.anydesk.*"),
            ("ToDesk cache", "Library/Caches/com.todesk.*"),
            ("Sunlogin cache", "Library/Caches/com.sunlogin.*")
        ]

        for (name, path) in remoteDesktopPaths {
            let expandedPath = homeDir.appendingPathComponent(path)
            if fileManager.fileExists(atPath: expandedPath.path) {
                let result = cleanDirectoryContents(at: expandedPath, dryRun: dryRun)
                if result > 0 {
                    results.append(CacheResult(
                        categoryName: name,
                        sizeBytes: getDirectorySize(expandedPath),
                        itemCount: result,
                        items: [expandedPath.path]
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Wildcard Path Expansion

    private func expandGlobPath(_ pattern: String, basePath: String) -> [String] {
        guard pattern.contains("*") else { return [pattern] }

        let directory = URL(fileURLWithPath: basePath).appendingPathComponent(
            (pattern as NSString).deletingLastPathComponent
        ).path
        let filename = (pattern as NSString).lastPathComponent

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }

        let regexPattern = "^" + filename
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*") + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return [] }

        return contents.filter { item in
            regex.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)) != nil
        }.map { item -> String in
            return directory + "/" + item
        }
    }
}

// MARK: - String Extension for Glob Matching

extension String {
    func matchesGlob(pattern: String) -> Bool {
        let regexPattern = "^" + pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".") + "$"

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else { return false }

        return regex.firstMatch(in: self, range: NSRange(self.startIndex..., in: self)) != nil
    }
}