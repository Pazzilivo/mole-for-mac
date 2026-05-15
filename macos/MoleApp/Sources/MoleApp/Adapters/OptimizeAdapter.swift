import Foundation

enum OptimizeAdapter {
    static func convert(
        results: [OptimizeEngine.OptimizeResult],
        memoryUsedGB: Double,
        memoryTotalGB: Double,
        diskUsedGB: Double,
        diskTotalGB: Double,
        diskUsedPercent: Double,
        uptimeDays: Double
    ) -> OptimizePlan {
        let tasks: [OptimizeTask] = results.map { result in
            let safe = result.success
            let category = categorize(result.taskName)
            return OptimizeTask(
                category: category,
                name: result.taskName,
                description: result.message,
                action: result.taskName.lowercased().replacingOccurrences(of: " ", with: "_"),
                safe: safe
            )
        }

        return OptimizePlan(
            memoryUsedGB: memoryUsedGB,
            memoryTotalGB: memoryTotalGB,
            diskUsedGB: diskUsedGB,
            diskTotalGB: diskTotalGB,
            diskUsedPercent: diskUsedPercent,
            uptimeDays: uptimeDays,
            optimizations: tasks
        )
    }

    static func buildPlan(
        memoryUsedGB: Double,
        memoryTotalGB: Double,
        diskUsedGB: Double,
        diskTotalGB: Double,
        diskUsedPercent: Double,
        uptimeDays: Double
    ) -> OptimizePlan {
        let tasks = defaultOptimizeTasks()
        return OptimizePlan(
            memoryUsedGB: memoryUsedGB,
            memoryTotalGB: memoryTotalGB,
            diskUsedGB: diskUsedGB,
            diskTotalGB: diskTotalGB,
            diskUsedPercent: diskUsedPercent,
            uptimeDays: uptimeDays,
            optimizations: tasks
        )
    }

    private static func defaultOptimizeTasks() -> [OptimizeTask] {
        [
            OptimizeTask(category: "system", name: "Flush DNS Cache", description: "Flush DNS cache to speed up network", action: "flush_dns", safe: true),
            OptimizeTask(category: "system", name: "Rebuild Launch Services", description: "Rebuild Launch Services database", action: "rebuild_launch_services", safe: true),
            OptimizeTask(category: "ui", name: "Refresh Dock", description: "Refresh Dock to clear icon cache", action: "refresh_dock", safe: true),
            OptimizeTask(category: "system", name: "Periodic Maintenance", description: "Run daily, weekly, monthly maintenance", action: "periodic_maintenance", safe: true),
            OptimizeTask(category: "cache", name: "Refresh Finder Caches", description: "Clear QuickLook and icon service caches", action: "refresh_finder_caches", safe: true),
            OptimizeTask(category: "cache", name: "Clean Quarantine Attributes", description: "Remove quarantine xattr from downloads", action: "clean_quarantine", safe: true),
            OptimizeTask(category: "cache", name: "Clean Saved Application States", description: "Remove saved application state files", action: "clean_saved_states", safe: true),
            OptimizeTask(category: "system", name: "Purge Memory Cache", description: "Purge inactive memory pages", action: "purge_memory", safe: true),
            OptimizeTask(category: "system", name: "Repair Disk Permissions", description: "Verify and repair disk permissions", action: "repair_permissions", safe: true),
        ]
    }

    private static func categorize(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("dns") || lower.contains("launch") || lower.contains("periodic") || lower.contains("memory") || lower.contains("permission") {
            return "system"
        }
        if lower.contains("cache") || lower.contains("finder") || lower.contains("quarantine") || lower.contains("saved") {
            return "cache"
        }
        if lower.contains("dock") {
            return "ui"
        }
        return "other"
    }
}
