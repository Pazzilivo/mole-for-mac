import SwiftUI

struct CleanPane: View {
    @EnvironmentObject private var model: MoleAppModel
    @State private var showCleanConfirmation = false

    private var targetCount: Int {
        model.cleanCategories.reduce(0) { $0 + $1.targets.count }
    }

    private var itemCount: Int {
        model.cleanCategories.reduce(0) { total, category in
            total + category.targets.reduce(0) { $0 + max($1.itemCount, 1) }
        }
    }

    private var highestRisk: CleanRiskLevel {
        model.cleanCategories.map(\.risk).max(by: { $0.severity < $1.severity }) ?? .low
    }

    private var riskCounts: [(CleanRiskLevel, Int)] {
        CleanRiskLevel.allCases.map { risk in
            (risk, model.cleanCategories.flatMap(\.targets).filter { $0.risk == risk }.count)
        }
    }

    var body: some View {
        Workspace(title: "Clean", subtitle: "Scan and remove caches, logs, temp files, and app leftovers.") {
            HStack {
                Button {
                    Task { await model.runCleanScan() }
                } label: {
                    Label(model.cleanState == .loading ? "Scanning..." : "Scan", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.cleanState == .loading)

                if model.cleanState == .loading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.cleanProgress.isEmpty ? "Scanning cleanup candidates..." : model.cleanProgress)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if model.cleanState == .ready {
                    Button {
                        showCleanConfirmation = true
                    } label: {
                        Label("Review & Clean", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(model.cleanState == .loading)
                }
            }

            if case let .failed(message) = model.cleanState {
                ErrorBanner(message: message)
            }

            if model.cleanState == .loading && !model.cleanOutput.isEmpty {
                ScrollView {
                    Text(model.cleanOutput)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 300)
            }

            if !model.cleanCategories.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Deletion Plan", icon: "list.bullet.clipboard")

                    HStack(spacing: 16) {
                        MetricStrip(items: [
                            ("Categories", "\(model.cleanCategories.count)"),
                            ("Targets", "\(targetCount)"),
                            ("Items", "\(itemCount)"),
                            ("Reclaimable", model.cleanTotalSize)
                        ])
                    }

                    CleanRiskSummary(highestRisk: highestRisk, counts: riskCounts)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.cleanCategories) { category in
                            CleanCategoryDisclosure(category: category)
                        }
                    }

                    ScrollView {
                        Text(model.cleanOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            } else if model.cleanState == .idle {
                EmptyState(
                    icon: "sparkles",
                    title: "Ready to clean",
                    detail: "Click Scan to find caches, logs, temp files, and other reclaimable space."
                )
            }
        }
        .alert("Clean selected plan?", isPresented: $showCleanConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clean \(model.cleanTotalSize)", role: .destructive) {
                Task { await model.runCleanApply() }
            }
        } message: {
            Text("Mole will remove \(targetCount) listed locations across \(model.cleanCategories.count) categories. Highest visible risk: \(highestRisk.title). Review high and medium risk rows before continuing.")
        }
    }
}

enum CleanRiskLevel: String, CaseIterable, Hashable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var severity: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    var icon: String {
        switch self {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }

    var explanation: String {
        switch self {
        case .low: return "Regenerable caches, logs, or temporary files."
        case .medium: return "May require rebuild, re-download, or app cache regeneration."
        case .high: return "Review carefully; this can affect backups, Trash, system, or app state."
        }
    }
}

struct CleanTarget: Identifiable {
    let id = UUID()
    let path: String
    let size: String
    let sizeBytes: Int64
    let itemCount: Int
    let risk: CleanRiskLevel
    let reason: String

    var name: String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? path : last
    }

    var parentPath: String {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        return parent == "/" ? parent : parent.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    var displayPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

struct CleanCategory: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let detail: String
    let icon: String
    let color: Color
    var risk: CleanRiskLevel = .medium
    var riskReason: String = ""
    var targets: [CleanTarget] = []
    var files: [String] = []

    var targetCountText: String {
        guard !targets.isEmpty else { return detail }
        let locations = targets.count == 1 ? "1 location" : "\(targets.count) locations"
        let items = targets.reduce(0) { $0 + max($1.itemCount, 1) }
        return "\(locations), \(items) items"
    }
}

private struct CleanRiskSummary: View {
    let highestRisk: CleanRiskLevel
    let counts: [(CleanRiskLevel, Int)]

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: highestRisk.icon)
                    .foregroundStyle(highestRisk.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Highest risk: \(highestRisk.title)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(highestRisk.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ForEach(CleanRiskLevel.allCases, id: \.self) { risk in
                let count = counts.first(where: { $0.0 == risk })?.1 ?? 0
                CleanRiskBadge(risk: risk, text: "\(risk.title) \(count)")
            }
        }
        .padding(12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CleanCategoryDisclosure: View {
    let category: CleanCategory
    private let previewLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(category.color)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.system(size: 13, weight: .medium))
                    if !category.targetCountText.isEmpty {
                        Text(category.targetCountText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                CleanRiskBadge(risk: category.risk, text: category.risk.title)
                Text(category.size)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(category.size == "--" ? .secondary : .primary)
                    .frame(minWidth: 78, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !category.riskReason.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: category.risk.icon)
                            .font(.system(size: 12))
                            .foregroundStyle(category.risk.color)
                            .frame(width: 16)
                        Text(category.riskReason)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if category.targets.isEmpty {
                    ForEach(category.files.prefix(previewLimit), id: \.self) { file in
                        Text(file)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    ForEach(category.targets.prefix(previewLimit)) { target in
                        CleanTargetRow(target: target)
                    }

                    if category.targets.count > previewLimit {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(category.targets.dropFirst(previewLimit)) { target in
                                    CleanTargetRow(target: target)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Label("\(category.targets.count - previewLimit) more locations", systemImage: "ellipsis.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.leading, 32)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CleanTargetRow: View {
    let target: CleanTarget

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: targetIcon)
                .font(.system(size: 12))
                .foregroundStyle(target.risk.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(target.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    CleanRiskBadge(risk: target.risk, text: target.risk.title)
                    Spacer()
                    Text(target.size)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Text(target.displayPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    Text(target.itemCount == 1 ? "1 item" : "\(target.itemCount) items")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(target.reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    private var targetIcon: String {
        if target.path.contains("/Trash") || target.name.localizedCaseInsensitiveContains("trash") {
            return "trash"
        }
        if target.path.hasSuffix(".log") || target.path.localizedCaseInsensitiveContains("/logs") {
            return "doc.text"
        }
        if target.path.localizedCaseInsensitiveContains("cache") {
            return "archivebox"
        }
        if target.path.localizedCaseInsensitiveContains("backup") {
            return "externaldrive.badge.timemachine"
        }
        return "folder"
    }
}

private struct CleanRiskBadge: View {
    let risk: CleanRiskLevel
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(risk.color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(risk.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(risk.color.opacity(0.10), in: Capsule())
    }
}

struct OptimizePane: View {
    @EnvironmentObject private var model: MoleAppModel

    private let plan = PlannedScreen(
        title: "Optimize",
        subtitle: "Run system refresh and repair tasks with clear sudo boundaries.",
        commands: [
            PlannedCommand(command: "mole optimize --plan-json", purpose: "Return task list with sudo requirement, whitelist state, and health context."),
            PlannedCommand(command: "mole optimize --apply-plan <plan-file>", purpose: "Apply selected tasks and stream task result events."),
            PlannedCommand(command: "mole optimize --whitelist", purpose: "Manage disabled optimization tasks.")
        ],
        safetyNotes: [
            "Sudo-required tasks are grouped before authentication.",
            "Whitelisted tasks stay disabled by default.",
            "Failed privileged tasks are skipped and reported.",
            "No repeated password prompt loops."
        ],
        availableNow: [
            "The existing optimize script can generate health JSON internally.",
            "A structured public plan command still needs to be added."
        ]
    )

    var body: some View {
        Workspace(title: "Optimize", subtitle: "Review system refresh tasks before anything changes.") {
            HStack {
                Button {
                    Task { await model.refreshOptimizePlan() }
                } label: {
                    Label("Load Plan", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.borderedProminent)

                if model.optimizeState == .loading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if case let .failed(message) = model.optimizeState {
                ErrorBanner(message: message)
            }

            if let optimizePlan = model.optimizePlan {
                VStack(alignment: .leading, spacing: 16) {
                    MetricStrip(items: [
                        ("Memory", "\(formatGB(optimizePlan.memoryUsedGB)) / \(formatGB(optimizePlan.memoryTotalGB)) GB"),
                        ("Disk", "\(formatGB(optimizePlan.diskUsedGB)) / \(formatGB(optimizePlan.diskTotalGB)) GB"),
                        ("Uptime", "\(formatNumber(optimizePlan.uptimeDays)) days")
                    ])

                    Table(optimizePlan.optimizations) {
                        TableColumn("Task", value: \.name)
                        TableColumn("Action", value: \.action)
                        TableColumn("Safe") { task in
                            Text(task.safe ? "Yes" : "Review")
                        }
                        TableColumn("Description") { task in
                            Text(task.description)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(minHeight: 380)
                }
            } else {
                PlannedFlowPane(plan: plan, showHeader: false)
            }
        }
    }
}

struct ArtifactsPane: View {
    @State private var selection: ArtifactMode = .projects

    var body: some View {
        Workspace(title: "Artifacts", subtitle: "Clean project build output and installer files with table-based selection.") {
            Picker("Mode", selection: $selection) {
                ForEach(ArtifactMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            PlannedFlowPane(plan: selection.plan, showHeader: false)
        }
    }
}

enum ArtifactMode: String, CaseIterable, Identifiable {
    case projects
    case installers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: return "Project Artifacts"
        case .installers: return "Installer Files"
        }
    }

    var plan: PlannedScreen {
        switch self {
        case .projects:
            return PlannedScreen(
                title: "Project Artifacts",
                subtitle: "Find old dependency and build folders such as node_modules, target, build, dist, and .build.",
                commands: [
                    PlannedCommand(command: "mole purge --list-json", purpose: "Return candidate artifacts with project path, type, size, age, and default selected state."),
                    PlannedCommand(command: "mole purge --apply-plan <plan-file>", purpose: "Delete selected artifact directories after parent/child dedupe."),
                    PlannedCommand(command: "mole purge --paths", purpose: "Manage scan roots.")
                ],
                safetyNotes: [
                    "Recent projects default to unselected.",
                    "Nested parent and child selections are deduplicated.",
                    "Scan roots must remain inside configured project boundaries."
                ],
                availableNow: [
                    "Interactive purge and dry-run exist.",
                    "Stable list/apply JSON commands are still missing."
                ]
            )
        case .installers:
            return PlannedScreen(
                title: "Installer Files",
                subtitle: "Find large DMG, PKG, ZIP, and app installer leftovers in common locations.",
                commands: [
                    PlannedCommand(command: "mole installer --list-json", purpose: "Return installer candidates with source, size, path, and age."),
                    PlannedCommand(command: "mole installer --apply-plan <plan-file>", purpose: "Remove selected installer files after confirmation.")
                ],
                safetyNotes: [
                    "Prefer Trash where practical.",
                    "Never follow symlinked installer candidates.",
                    "Surface source labels such as Downloads, Homebrew, Mail, or iCloud."
                ],
                availableNow: [
                    "Interactive installer cleanup and dry-run exist.",
                    "Stable JSON list/apply commands are still missing."
                ]
            )
        }
    }
}

struct LogsPane: View {
    @EnvironmentObject private var model: MoleAppModel
    @State private var mode: LogMode = .operations

    var body: some View {
        Workspace(title: "Logs", subtitle: "Review cleanup and deletion history from Mole's audit logs.") {
            HStack {
                Picker("Log", selection: $mode) {
                    ForEach(LogMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Button {
                    model.refreshLogs()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            if case let .failed(message) = model.logsState {
                ErrorBanner(message: message)
            }

            switch mode {
            case .operations:
                OperationsLogTable(entries: model.operationLog)
            case .deletions:
                DeletionsLogTable(entries: model.deletionLog)
            }
        }
        .onAppear {
            if model.logsState == .idle {
                model.refreshLogs()
            }
        }
    }
}

enum LogMode: String, CaseIterable, Identifiable {
    case operations
    case deletions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .operations: return "Operations"
        case .deletions: return "Deletions"
        }
    }
}

struct OperationsLogTable: View {
    let entries: [OperationLogEntry]

    var body: some View {
        if entries.isEmpty {
            EmptyState(title: "No operation log entries", detail: "Run a dry-run or cleanup command to create operation logs.")
        } else {
            Table(entries) {
                TableColumn("Time") { entry in
                    Text(entry.timestamp.isEmpty ? "-" : entry.timestamp)
                        .monospacedDigit()
                }
                TableColumn("Command", value: \.command)
                TableColumn("Action", value: \.action)
                TableColumn("Path") { entry in
                    Text(entry.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("Detail", value: \.detail)
            }
            .frame(minHeight: 480)
        }
    }
}

struct DeletionsLogTable: View {
    let entries: [DeletionLogEntry]

    var body: some View {
        if entries.isEmpty {
            EmptyState(title: "No deletion log entries", detail: "Trash-routed uninstall actions will appear here.")
        } else {
            Table(entries) {
                TableColumn("Time") { entry in
                    Text(entry.timestamp)
                        .monospacedDigit()
                }
                TableColumn("Mode", value: \.mode)
                TableColumn("Status", value: \.status)
                TableColumn("Size KB", value: \.sizeKB)
                TableColumn("Path") { entry in
                    Text(entry.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minHeight: 480)
        }
    }
}

struct PlannedFlowPane: View {
    let plan: PlannedScreen
    var showHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showHeader {
                Workspace(title: plan.title, subtitle: plan.subtitle) {
                    plannedContent
                }
            } else {
                plannedContent
            }
        }
    }

    private var plannedContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Available now")
                    .font(.headline)
                BulletList(items: plan.availableNow)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Required API")
                    .font(.headline)
                ForEach(plan.commands) { command in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(command.command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text(command.purpose)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Safety")
                    .font(.headline)
                BulletList(items: plan.safetyNotes)
            }
        }
    }
}

struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private func formatGB(_ value: Double?) -> String {
    guard let value else { return "0" }
    return String(format: "%.1f", value)
}

private func formatNumber(_ value: Double?) -> String {
    guard let value else { return "0" }
    return String(format: "%.1f", value)
}
