import Foundation

/// Thread-safe whitelist pattern management
actor WhitelistManager {
    // MARK: - Constants
    private static let finderMetadataSentinel = "__FINDER_METADATA__"

    // MARK: - Properties
    private(set) var patterns: [String] = []
    private(set) var protectFinderMetadata: Bool = false

    // MARK: - Default Whitelist Patterns
    private static let defaultPatterns: [String] = [
        "~/Library/Caches/ms-playwright*",
        "~/.cache/huggingface*",
        "~/.m2/repository/*",
        "~/.gradle/caches/*",
        "~/.gradle/daemon/*",
        "~/.ollama/models/*",
        "~/Library/Caches/com.nssurge.surge-mac/*",
        "~/Library/Application Support/com.nssurge.surge-mac/*",
        "~/Library/Caches/org.R-project.R/R/renv/*",
        "~/Library/Caches/pypoetry/virtualenvs*",
        "~/Library/Caches/JetBrains*",
        "~/Library/Caches/com.jetbrains.toolbox*",
        "~/Library/Caches/tealdeer/tldr-pages",
        "~/Library/Application Support/JetBrains*",
        "~/Library/Caches/com.apple.finder",
        "~/Library/Mobile Documents*",
        // System-critical caches that affect macOS functionality and stability
        "~/Library/Caches/com.apple.FontRegistry*",
        "~/Library/Caches/com.apple.spotlight*",
        "~/Library/Caches/com.apple.Spotlight*",
        "~/Library/Caches/CloudKit*",
        finderMetadataSentinel
    ]

    // MARK: - Initialization
    init() {
        loadDefaultPatterns()
    }

    // MARK: - Pattern Loading
    func loadDefaultPatterns() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path

        patterns = Self.defaultPatterns.map { pattern in
            expandedPath(pattern, homeDirectory: homeDirectory)
        }

        checkFinderMetadataProtection()
    }

    func loadPatterns(from url: URL) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let loadedPatterns = parsePatterns(from: contents)

        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path

        patterns = loadedPatterns.map { pattern in
            expandedPath(pattern, homeDirectory: homeDirectory)
        }

        checkFinderMetadataProtection()
    }

    func addPattern(_ pattern: String) {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let expandedPattern = expandedPath(pattern, homeDirectory: homeDirectory)

        guard !patterns.contains(expandedPattern) else { return }

        patterns.append(expandedPattern)

        if expandedPattern == Self.finderMetadataSentinel {
            protectFinderMetadata = true
        }
    }

    func removePattern(_ pattern: String) {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let expandedPattern = expandedPath(pattern, homeDirectory: homeDirectory)

        patterns.removeAll { $0 == expandedPattern }

        if expandedPattern == Self.finderMetadataSentinel {
            protectFinderMetadata = false
        }
    }

    // MARK: - Pattern Matching
    func isWhitelisted(_ path: String) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath

        for pattern in patterns {
            let normalizedPattern = (pattern as NSString).standardizingPath

            // Check for sentinel
            if normalizedPattern == Self.finderMetadataSentinel {
                continue // This is handled by protectFinderMetadata
            }

            // Exact match
            if normalizedPath == normalizedPattern {
                return true
            }

            // Wildcard pattern matching
            if patternContainsWildcard(normalizedPattern) {
                let regexPattern = convertWildcardToRegex(normalizedPattern)
                if let regex = try? NSRegularExpression(pattern: regexPattern, options: []) {
                    let range = NSRange(location: 0, length: normalizedPath.utf16.count)
                    if regex.firstMatch(in: normalizedPath, options: [], range: range) != nil {
                        return true
                    }
                }
            }

            // Check if path is a parent directory of whitelisted path
            if normalizedPattern.hasPrefix(normalizedPath + "/") {
                return true
            }

            // Check if path is a child of a whitelisted directory (non-wildcard patterns only)
            if !patternContainsWildcard(normalizedPattern) && normalizedPath.hasPrefix(normalizedPattern + "/") {
                return true
            }
        }

        return false
    }

    func shouldProtectFinderMetadata() -> Bool {
        return protectFinderMetadata
    }

    // MARK: - Validation
    func validatePattern(_ pattern: String) -> Bool {
        // Check for path traversal
        if pattern.contains("..") {
            return false
        }

        // Check for control characters
        if pattern.contains(where: { $0.isPathControlCharacter }) {
            return false
        }

        // Check for consecutive slashes
        if pattern.contains("//") {
            return false
        }

        let expandedPattern = expandedPath(pattern, homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path)

        // Check if it's an absolute path (unless it contains wildcards)
        if !patternContainsWildcard(expandedPattern) && !expandedPattern.hasPrefix("/") {
            return false
        }

        // Check for protected system paths
        let protectedPaths = [
            "/",
            "/System",
            "/System/*",
            "/bin",
            "/bin/*",
            "/sbin",
            "/sbin/*",
            "/usr/bin",
            "/usr/bin/*",
            "/usr/sbin",
            "/usr/sbin/*",
            "/etc",
            "/etc/*",
            "/var/db",
            "/var/db/*"
        ]

        for protectedPath in protectedPaths {
            if expandedPattern == protectedPath || expandedPattern.hasPrefix(protectedPath + "/") {
                return false
            }
        }

        return true
    }

    // MARK: - Utilities
    func getAllPatterns() -> [String] {
        return patterns
    }

    func getPatternCount() -> Int {
        return patterns.count
    }

    func exportPatterns(to url: URL) throws {
        let content = patterns.joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private Helpers
    private func parsePatterns(from content: String) -> [String] {
        var parsedPatterns: [String] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines and comments
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            // Validate pattern
            if validatePattern(trimmedLine) {
                parsedPatterns.append(trimmedLine)
            }
        }

        return parsedPatterns
    }

    private func expandedPath(_ pattern: String, homeDirectory: String) -> String {
        var expandedPattern = pattern

        // Expand ~
        if expandedPattern.hasPrefix("~") {
            expandedPattern = String(expandedPattern.dropFirst())
            expandedPattern = homeDirectory + expandedPattern
        }

        // Expand $HOME
        if expandedPattern.hasPrefix("$HOME") {
            expandedPattern = String(expandedPattern.dropFirst(5))
            expandedPattern = homeDirectory + expandedPattern
        }

        // Expand ${HOME}
        if expandedPattern.hasPrefix("${HOME}") {
            expandedPattern = String(expandedPattern.dropFirst(7))
            expandedPattern = homeDirectory + expandedPattern
        }

        return expandedPattern
    }

    private func patternContainsWildcard(_ pattern: String) -> Bool {
        return pattern.contains("*") || pattern.contains("?") || pattern.contains("[")
    }

    private func convertWildcardToRegex(_ pattern: String) -> String {
        var regex = NSRegularExpression.escapedPattern(for: pattern)

        // Convert * to .*
        regex = regex.replacingOccurrences(of: "\\*", with: ".*")

        // Convert ? to .
        regex = regex.replacingOccurrences(of: "\\?", with: ".")

        // Convert [...] to character class
        // This is simplified; a full implementation would handle ranges and negations
        regex = regex.replacingOccurrences(of: "\\[", with: "[")
        regex = regex.replacingOccurrences(of: "\\]", with: "]")

        // Add anchors
        regex = "^" + regex + "$"

        return regex
    }

    private func checkFinderMetadataProtection() {
        protectFinderMetadata = patterns.contains(Self.finderMetadataSentinel)
    }
}

// MARK: - Character Extension
extension Character {
    var isPathControlCharacter: Bool {
        return self.isASCII && self.unicodeScalars.first?.properties.generalCategory == .control
    }
}

// MARK: - Whitelist Pattern Type
enum WhitelistPatternType {
    case literal
    case wildcard
    case regex
    case sentinel
}

struct WhitelistPattern {
    let original: String
    let expanded: String
    let type: WhitelistPatternType
    let isSystemDefault: Bool

    var isValid: Bool {
        // Basic validation
        if expanded.contains("..") {
            return false
        }

        if expanded.contains(where: { $0.isPathControlCharacter }) {
            return false
        }

        if expanded.contains("//") {
            return false
        }

        // Must be absolute path (unless wildcard)
        if type != .wildcard && type != .regex && !expanded.hasPrefix("/") {
            return false
        }

        return true
    }

    func matches(_ path: String) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath
        let normalizedPattern = (expanded as NSString).standardizingPath

        switch type {
        case .literal:
            return normalizedPath == normalizedPattern ||
                   normalizedPath.hasPrefix(normalizedPattern + "/") ||
                   normalizedPattern.hasPrefix(normalizedPath + "/")

        case .wildcard, .regex:
            if let regex = try? NSRegularExpression(pattern: convertToRegex(), options: []) {
                let range = NSRange(location: 0, length: normalizedPath.utf16.count)
                return regex.firstMatch(in: normalizedPath, options: [], range: range) != nil
            }
            return false

        case .sentinel:
            return false // Sentinels are handled separately
        }
    }

    private func convertToRegex() -> String {
        var regex = NSRegularExpression.escapedPattern(for: expanded)
        regex = regex.replacingOccurrences(of: "\\*", with: ".*")
        regex = regex.replacingOccurrences(of: "\\?", with: ".")
        return "^" + regex + "$"
    }
}