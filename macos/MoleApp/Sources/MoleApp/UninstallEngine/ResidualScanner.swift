import Foundation

// MARK: - Residual File Scanner
actor ResidualScanner {

    // MARK: - Dependencies
    private let safeRemover = UninstallSafeRemover()

    // MARK: - Pre-compiled regex templates
    private struct CompiledPattern {
        let basePath: String
        let regexTemplate: String  // template with __BID__, __VENDOR__, __GROUP__, __APPNAME__ placeholders
        let category: ResidualFile.ResidualCategory
        let riskLevel: ResidualFile.RiskLevel
        let description: String
    }

    private let compiledPatterns: [CompiledPattern]

    // MARK: - Scan Patterns
    private let scanPatterns: [ResidualPattern] = [
        // Application Support
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Application Support",
            pattern: "{bundleId}*",
            category: .support,
            riskLevel: .moderate,
            description: "Application Support files"
        ),

        // Preferences
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Preferences",
            pattern: "com.{vendor}.*",
            category: .preference,
            riskLevel: .moderate,
            description: "Application preferences"
        ),

        // Caches
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Caches",
            pattern: "{bundleId}*",
            category: .cache,
            riskLevel: .safe,
            description: "Cache files"
        ),

        // Logs
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Logs",
            pattern: "{bundleId}*",
            category: .log,
            riskLevel: .safe,
            description: "Log files"
        ),

        // Launch Agents
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/LaunchAgents",
            pattern: "com.{vendor}.*",
            category: .launchAgent,
            riskLevel: .caution,
            description: "Launch agents"
        ),

        // Launch Daemons (system level)
        ResidualPattern(
            basePath: "/Library/LaunchAgents",
            pattern: "com.{vendor}.*",
            category: .launchAgent,
            riskLevel: .caution,
            description: "Launch agents (system)"
        ),

        // WebKit Data
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/WebKit",
            pattern: "{bundleId}",
            category: .webkit,
            riskLevel: .moderate,
            description: "WebKit data"
        ),

        // Containers
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Containers",
            pattern: "{bundleId}",
            category: .container,
            riskLevel: .moderate,
            description: "App containers"
        ),

        // Group Containers
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Group Containers",
            pattern: "{group}",
            category: .container,
            riskLevel: .moderate,
            description: "Group containers"
        ),

        // Saved Application State
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Saved Application State",
            pattern: "{bundleId}.*",
            category: .savedAppState,
            riskLevel: .safe,
            description: "Saved application state"
        ),

        // HTTP Storage
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/HTTPStorages",
            pattern: "{bundleId}",
            category: .httpStorage,
            riskLevel: .safe,
            description: "HTTP storage"
        ),

        // HTTP Cookies
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/HTTPCookies",
            pattern: "{bundleId}",
            category: .cookies,
            riskLevel: .caution,
            description: "HTTP cookies"
        ),

        // ByHost Preferences
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Preferences/ByHost",
            pattern: "{bundleId}.*",
            category: .preference,
            riskLevel: .moderate,
            description: "ByHost preferences"
        ),

        // Cookies
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/Library/Cookies",
            pattern: "{bundleId}*",
            category: .cookies,
            riskLevel: .caution,
            description: "Cookie files"
        ),

        // Trash
        ResidualPattern(
            basePath: "\(NSHomeDirectory())/.Trash",
            pattern: "{appname}*",
            category: .trash,
            riskLevel: .safe,
            description: "Trash files"
        )
    ]

    init() {
        // Pre-compile regex templates at init time
        self.compiledPatterns = scanPatterns.map { pattern in
            let template = Self.convertShellPatternToRegexTemplate(pattern.pattern)
            return CompiledPattern(
                basePath: pattern.basePath,
                regexTemplate: template,
                category: pattern.category,
                riskLevel: pattern.riskLevel,
                description: pattern.description
            )
        }
    }

    // MARK: - Public Methods

    /// Find residual files for a given bundle ID
    func findResidualFiles(bundleId: String, appName: String) async throws -> [ResidualFile] {
        var residuals: [ResidualFile] = []
        let vendor = extractVendor(from: bundleId)
        let groupIdentifier = extractGroupIdentifier(from: bundleId)

        // Build substitution map
        let subs: [String: String] = [
            "__BID__": NSRegularExpression.escapedPattern(for: bundleId),
            "__VENDOR__": NSRegularExpression.escapedPattern(for: vendor),
            "__GROUP__": NSRegularExpression.escapedPattern(for: groupIdentifier),
            "__APPNAME__": NSRegularExpression.escapedPattern(for: appName)
        ]

        // Compile final regexes grouped by basePath
        var pathGroups: [String: [(NSRegularExpression, CompiledPattern)]] = [:]
        for cp in compiledPatterns {
            var regexStr = cp.regexTemplate
            for (placeholder, escapedValue) in subs {
                regexStr = regexStr.replacingOccurrences(of: placeholder, with: escapedValue)
            }
            if let regex = try? NSRegularExpression(pattern: regexStr) {
                pathGroups[cp.basePath, default: []].append((regex, cp))
            }
        }

        // Single traversal per unique basePath
        for (basePath, patterns) in pathGroups {
            let found = await scanBasePath(
                basePath: basePath,
                patterns: patterns
            )
            residuals.append(contentsOf: found)
        }

        return residuals
    }

    // MARK: - Private Methods

    private func scanBasePath(
        basePath: String,
        patterns: [(NSRegularExpression, CompiledPattern)]
    ) async -> [ResidualFile] {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: basePath) else {
            return []
        }

        var results: [ResidualFile] = []

        do {
            let baseURL = URL(fileURLWithPath: basePath)

            if let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) {
                for case let url as URL in enumerator {
                    let fileName = url.lastPathComponent
                    let nsFileName = fileName as NSString
                    let range = NSRange(location: 0, length: nsFileName.length)

                    for (regex, cp) in patterns {
                        if regex.firstMatch(in: fileName, range: range) != nil {
                            if await safeRemover.isProtectedPath(url) {
                                continue
                            }

                            // Prefetched file size from enumerator
                            let size: Int64
                            if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]),
                               let allocatedSize = resourceValues.totalFileAllocatedSize {
                                size = Int64(allocatedSize)
                            } else if let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                                size = Int64(fileSize)
                            } else {
                                size = await getFileSize(at: url)
                            }

                            let residual = ResidualFile(
                                path: url,
                                size: size,
                                category: cp.category,
                                riskLevel: cp.riskLevel,
                                description: cp.description
                            )

                            results.append(residual)
                            break  // Match found for this file, no need to check other patterns
                        }
                    }
                }
            }
        } catch {
            return []
        }

        return results
    }

    private func extractVendor(from bundleId: String) -> String {
        let components = bundleId.split(separator: ".")
        if components.count >= 2 {
            return String(components[1])
        }
        return bundleId
    }

    private func extractGroupIdentifier(from bundleId: String) -> String {
        // Try to extract group identifier from bundle ID
        // Usually something like "group.com.example.app"
        return "group.\(bundleId)"
    }

    private static func convertShellPatternToRegexTemplate(_ pattern: String) -> String {
        // Replace placeholders before escaping
        var working = pattern
        working = working.replacingOccurrences(of: "{bundleId}", with: "__BID__")
        working = working.replacingOccurrences(of: "{vendor}", with: "__VENDOR__")
        working = working.replacingOccurrences(of: "{group}", with: "__GROUP__")
        working = working.replacingOccurrences(of: "{appname}", with: "__APPNAME__")

        // Escape regex special characters (placeholders use __ prefix so they won't be escaped)
        let specialChars: Set<Character> = ["\\", "^", "$", ".", "|", "?", "+", "(", ")", "[", "]", "{", "}"]
        var escaped = ""
        for char in working {
            if char == "*" {
                escaped.append(".*")
            } else if specialChars.contains(char) {
                escaped.append("\\")
                escaped.append(char)
            } else {
                escaped.append(char)
            }
        }

        return "^\(escaped)$"
    }

    private func getFileSize(at url: URL) async -> Int64 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fileManager = FileManager.default

                do {
                    let attributes = try fileManager.attributesOfItem(atPath: url.path)
                    if let fileSize = attributes[.size] as? Int64 {
                        continuation.resume(returning: fileSize)
                    } else {
                        continuation.resume(returning: 0)
                    }
                } catch {
                    continuation.resume(returning: 0)
                }
            }
        }
    }

    // MARK: - Supporting Types

    private struct ResidualPattern {
        let basePath: String
        let pattern: String
        let category: ResidualFile.ResidualCategory
        let riskLevel: ResidualFile.RiskLevel
        let description: String
    }
}