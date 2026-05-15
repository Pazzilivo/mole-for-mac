import Foundation
import SwiftUI

enum CleanAdapter {
    static func convertCacheResults(_ results: [AppCacheCleaner.CacheResult]) -> [CleanCategory] {
        results.compactMap { result in
            guard result.sizeBytes > 0 else { return nil }
            let size = ByteCountFormatter.string(fromByteCount: result.sizeBytes, countStyle: .file)
            let presentation = categoryPresentation(for: result.categoryName)
            let risk = classifyRisk(for: result.categoryName, sizeBytes: result.sizeBytes)

            let targets: [CleanTarget] = result.items.map { path in
                CleanTarget(
                    path: path,
                    size: size,
                    sizeBytes: result.sizeBytes,
                    itemCount: result.itemCount,
                    risk: risk,
                    reason: riskReason(for: result.categoryName, risk: risk)
                )
            }

            return CleanCategory(
                name: result.categoryName,
                size: size,
                detail: "\(result.itemCount) items",
                icon: presentation.icon,
                color: presentation.color,
                risk: risk,
                riskReason: riskReason(for: result.categoryName, risk: risk),
                targets: targets,
                files: result.items
            )
        }
    }

    static func convert(_ items: [CleanItem]) -> [CleanCategory] {
        let grouped = Dictionary(grouping: items) { $0.category }

        return grouped.map { category, categoryItems in
            let totalBytes = categoryItems.reduce(Int64(0)) { $0 + $1.size }
            let size = totalBytes > 0
                ? ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                : "--"
            let presentation = categoryPresentation(for: category.rawValue)
            let highestRisk = categoryItems.map(\.riskLevel).max() ?? .low

            let targets: [CleanTarget] = categoryItems.map { item in
                CleanTarget(
                    path: item.path,
                    size: ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file),
                    sizeBytes: item.size,
                    itemCount: 1,
                    risk: convertEngineRisk(item.riskLevel),
                    reason: item.riskLevel.description
                )
            }

            let cleanRisk = convertEngineRisk(highestRisk)

            return CleanCategory(
                name: category.rawValue,
                size: size,
                detail: "\(targets.count) locations, \(categoryItems.count) items",
                icon: presentation.icon,
                color: presentation.color,
                risk: cleanRisk,
                riskReason: riskReason(for: category.rawValue, risk: cleanRisk),
                targets: targets,
                files: categoryItems.map(\.path)
            )
        }
        .sorted { $0.name < $1.name }
    }

    static func convertEngineRisk(_ risk: RiskLevel) -> CleanRiskLevel {
        switch risk {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }

    private static func classifyRisk(for name: String, sizeBytes: Int64) -> CleanRiskLevel {
        let lower = name.lowercased()
        if lower.contains("system") || lower.contains("trash") {
            return .high
        }
        if lower.contains("xcode") || lower.contains("derived") || lower.contains("developer") {
            return .medium
        }
        if sizeBytes >= 1_073_741_824 {
            return .medium
        }
        return .low
    }

    private static func riskReason(for name: String, risk: CleanRiskLevel) -> String {
        switch risk {
        case .high:
            return "System or critical path; review before deleting."
        case .medium:
            return "Cache data that may regenerate after cleaning."
        case .low:
            return "Safe to clean."
        }
    }

    private static func categoryPresentation(for section: String) -> (icon: String, color: Color) {
        let lower = section.lowercased()
        if lower.contains("system") { return ("gearshape", .purple) }
        if lower.contains("user") { return ("archivebox", .blue) }
        if lower.contains("xcode") || lower.contains("derived") { return ("hammer", .blue) }
        if lower.contains("simulator") { return ("hammer", .blue) }
        if lower.contains("application") || lower.contains("app cache") { return ("internaldrive", .teal) }
        if lower.contains("log") { return ("doc.text", .orange) }
        if lower.contains("temp") { return ("clock", .purple) }
        if lower.contains("browser") || lower.contains("safari") { return ("globe", .orange) }
        if lower.contains("develop") || lower.contains("code") || lower.contains("zed") { return ("hammer", .blue) }
        if lower.contains("discord") || lower.contains("slack") || lower.contains("zoom") || lower.contains("chat") || lower.contains("telegram") || lower.contains("wechat") || lower.contains("teams") || lower.contains("feishu") { return ("message", .indigo) }
        if lower.contains("container") { return ("box", .indigo) }
        if lower.contains("leftover") || lower.contains("orphan") || lower.contains("residual") { return ("questionmark.folder", .red) }
        if lower.contains("download") { return ("arrow.down.circle", .secondary) }
        if lower.contains("trash") { return ("trash", .green) }
        if lower.contains("sketch") || lower.contains("adobe") || lower.contains("figma") { return ("paintbrush", .pink) }
        if lower.contains("blender") || lower.contains("cinema") || lower.contains("sketchup") { return ("cube", .orange) }
        if lower.contains("final cut") || lower.contains("screenflow") || lower.contains("davinci") || lower.contains("premiere") { return ("film", .purple) }
        if lower.contains("brew") || lower.contains("homebrew") { return ("mug", .orange) }
        if lower.contains("chatgpt") || lower.contains("claude") || lower.contains("copilot") { return ("cpu", .green) }
        if lower.contains("node") || lower.contains("npm") || lower.contains("yarn") || lower.contains("bun") || lower.contains("pnpm") { return ("cube", .green) }
        if lower.contains("cargo") || lower.contains("rust") { return ("cube", .orange) }
        if lower.contains("pod") || lower.contains("cocoapods") || lower.contains("spm") { return ("cube", .blue) }
        return ("folder", .secondary)
    }
}
