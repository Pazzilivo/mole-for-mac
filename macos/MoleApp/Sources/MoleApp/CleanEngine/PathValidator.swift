import Foundation

/// Thread-safe path validation for cleaning operations
actor PathValidator {
    // MARK: - Protected Path Patterns
    private static let systemCriticalPaths: Set<String> = [
        "/",
        "/bin",
        "/sbin",
        "/usr",
        "/usr/bin",
        "/usr/sbin",
        "/usr/lib",
        "/System",
        "/Library/Extensions",
        "/private/etc",
        "/private/var/db",
        "/etc",
        "/var/db"
    ]

    private static let allowedPrivatePaths: Set<String> = [
        "/private/tmp",
        "/private/var/tmp",
        "/private/var/log",
        "/private/var/folders",
        "/private/var/db/diagnostics",
        "/private/var/db/DiagnosticPipeline",
        "/private/var/db/powerlog",
        "/private/var/db/reportmemoryexception"
    ]

    private static let allowedSystemCaches: Set<String> = [
        "/System/Library/Caches/com.apple.coresymbolicationd/data"
    ]

    // MARK: - Validation
    func validate(_ path: String) -> ValidationResult {
        var errors: [ValidationError] = []
        var warnings: [ValidationWarning] = []

        // Check if path is empty
        if path.isEmpty {
            errors.append(.emptyPath)
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // Check if path is absolute
        if !path.hasPrefix("/") {
            errors.append(.relativePath(path))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // Check for path traversal attempts
        if path.contains("..") {
            errors.append(.pathTraversal(path))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // Check for control characters and newlines
        if path.contains(where: { $0.isPathControlCharacter && $0 != "\n" }) || path.contains("\n") {
            errors.append(.invalidCharacters(path))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // Check for consecutive slashes
        if path.contains("//") {
            errors.append(.invalidCharacters(path))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // Check for system-critical paths
        let normalizedPath = (path as NSString).standardizingPath
        if isSystemCriticalPath(normalizedPath) {
            errors.append(.protectedSystemPath(path))
            return ValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // Check symbolic link targets
        if let linkTarget = getSymbolicLinkTarget(path) {
            if isSystemCriticalPath(linkTarget) {
                errors.append(.symbolicLinkTarget(linkTarget))
                return ValidationResult(isValid: false, errors: errors, warnings: warnings)
            }
        }

        // Generate warnings for potentially risky operations
        warnings.append(contentsOf: generateWarnings(for: normalizedPath))

        return ValidationResult(
            isValid: true,
            errors: errors,
            warnings: warnings
        )
    }

    // MARK: - Private Helpers
    private func isSystemCriticalPath(_ path: String) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath

        // Check against system critical paths
        for criticalPath in Self.systemCriticalPaths {
            if normalizedPath == criticalPath || normalizedPath.hasPrefix(criticalPath + "/") {
                // Check if it's an allowed exception
                if Self.allowedPrivatePaths.contains(where: { normalizedPath.hasPrefix($0 + "/") }) ||
                   Self.allowedSystemCaches.contains(where: { normalizedPath.hasPrefix($0 + "/") }) {
                    return false
                }
                return true
            }
        }

        return false
    }

    private func getSymbolicLinkTarget(_ path: String) -> String? {
        do {
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: path)
            let absoluteTarget: String
            if (target as NSString).isAbsolutePath {
                absoluteTarget = target
            } else {
                let parentDir = (path as NSString).deletingLastPathComponent
                absoluteTarget = (parentDir as NSString).appendingPathComponent(target)
            }
            return (absoluteTarget as NSString).standardizingPath
        } catch {
            return nil
        }
    }

    private func generateWarnings(for path: String) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []

        // Check if file is large
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let fileSize = attributes[.size] as? Int64,
           fileSize > 100_000_000 { // 100 MB
            warnings.append(.largeFile(size: fileSize, path: path))
        }

        // Check if recently accessed
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let accessDate = attributes[.modificationDate] as? Date {
            let daysSinceAccess = Date().timeIntervalSince(accessDate) / 86400
            if daysSinceAccess < 7 { // Accessed within last 7 days
                warnings.append(.recentlyAccessed(path: path, date: accessDate))
            }
        }

        // Check for unusual permissions
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           let permissions = attributes[.posixPermissions] as? UInt16 {
            let octalPermissions = permissions & 0o777
            // World-writable files are unusual
            if octalPermissions & 0o002 != 0 {
                warnings.append(.unusualPermissions(path: path))
            }
        }

        // Check if on network volume
        if isNetworkVolume(path) {
            warnings.append(.networkVolume(path: path))
        }

        return warnings
    }

    private func isNetworkVolume(_ path: String) -> Bool {
        do {
            let url = URL(fileURLWithPath: path)
            let resourceValues = try url.resourceValues(forKeys: [.volumeIsLocalKey])
            return !(resourceValues.volumeIsLocal ?? true)
        } catch {
            return false
        }
    }

    // MARK: - Public Utilities
    func inspect(_ path: String) -> PathInspectionResult? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }

        let fileType = attributes[.type] as? FileAttributeType
        let cleanType: CleanItem.CleanType
        switch fileType {
        case .typeDirectory:
            cleanType = .directory
        case .typeSymbolicLink:
            cleanType = .symlink
        case .typeRegular:
            // Check if it's an app bundle
            if path.hasSuffix(".app") {
                cleanType = .bundle
            } else {
                cleanType = .file
            }
        default:
            cleanType = .file
        }

        let size = (attributes[.size] as? Int64) ?? 0
        let lastAccessed = attributes[.modificationDate] as? Date
        let lastModified = attributes[.modificationDate] as? Date

        let permissions = extractPermissions(from: attributes)

        // Estimate risk and category based on path characteristics
        let riskLevel = estimateRiskLevel(for: path, type: cleanType, size: size)
        let category = suggestCategory(for: path, type: cleanType)

        return PathInspectionResult(
            path: path,
            exists: true,
            isReadable: FileManager.default.isReadableFile(atPath: path),
            isWritable: FileManager.default.isWritableFile(atPath: path),
            size: size,
            type: cleanType,
            lastAccessed: lastAccessed,
            lastModified: lastModified,
            permissions: permissions,
            estimatedRisk: riskLevel,
            suggestedCategory: category
        )
    }

    private func extractPermissions(from attributes: [FileAttributeKey: Any]) -> PathInspectionResult.FilePermissions {
        guard let permissions = attributes[.posixPermissions] as? UInt16 else {
            return PathInspectionResult.FilePermissions(
                ownerRead: false, ownerWrite: false, ownerExecute: false,
                groupRead: false, groupWrite: false, groupExecute: false,
                otherRead: false, otherWrite: false, otherExecute: false
            )
        }

        return PathInspectionResult.FilePermissions(
            ownerRead: (permissions & 0o400) != 0,
            ownerWrite: (permissions & 0o200) != 0,
            ownerExecute: (permissions & 0o100) != 0,
            groupRead: (permissions & 0o040) != 0,
            groupWrite: (permissions & 0o020) != 0,
            groupExecute: (permissions & 0o010) != 0,
            otherRead: (permissions & 0o004) != 0,
            otherWrite: (permissions & 0o002) != 0,
            otherExecute: (permissions & 0o001) != 0
        )
    }

    private func estimateRiskLevel(for path: String, type: CleanItem.CleanType, size: Int64) -> RiskLevel {
        // High risk paths
        let highRiskPatterns = [
            "/System",
            "/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "Preferences",
            "Keychains",
            "Mail",
            "Calendars",
            "Contacts"
        ]

        for pattern in highRiskPatterns {
            if path.contains(pattern) {
                return .high
            }
        }

        // Medium risk paths
        let mediumRiskPatterns = [
            "Application Support",
            "Caches",
            "Containers",
            ".app"
        ]

        for pattern in mediumRiskPatterns {
            if path.contains(pattern) {
                return .medium
            }
        }

        // Low risk paths
        let lowRiskPatterns = [
            "tmp",
            "temp",
            "cache",
            "log",
            "trash",
            ".Trash",
            "Downloads"
        ]

        for pattern in lowRiskPatterns {
            if path.lowercased().contains(pattern.lowercased()) {
                return .low
            }
        }

        // Default to medium for unknown paths
        return .medium
    }

    private func suggestCategory(for path: String, type: CleanItem.CleanType) -> CleanItemCategory {
        let lowercasedPath = path.lowercased()

        if lowercasedPath.contains("cache") {
            return lowercasedPath.contains("/system/") ? .systemCaches : .userCaches
        } else if lowercasedPath.contains("log") {
            return .logFiles
        } else if lowercasedPath.contains("tmp") || lowercasedPath.contains("temp") {
            return .temporaryFiles
        } else if lowercasedPath.contains("/library/containers/") {
            return .containers
        } else if lowercasedPath.contains("application support") {
            return .applicationSupport
        } else if lowercasedPath.contains("download") {
            return .downloads
        } else if lowercasedPath.contains("trash") || lowercasedPath.contains(".trash") {
            return .trash
        } else if lowercasedPath.contains("browser") ||
                lowercasedPath.contains("safari") ||
                lowercasedPath.contains("chrome") ||
                lowercasedPath.contains("firefox") {
            return .browserData
        } else if lowercasedPath.contains("developer") ||
                lowercasedPath.contains("xcode") ||
                lowercasedPath.contains("android") ||
                lowercasedPath.contains("gradle") ||
                lowercasedPath.contains("maven") ||
                lowercasedPath.contains("node_modules") {
            return .developmentTools
        } else if type == .bundle {
            return .applicationCaches
        } else {
            return .other
        }
    }
}

