import SwiftUI

struct CleanPane: View {
    @EnvironmentObject private var model: MoleAppModel

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
                        Task { await model.runCleanApply() }
                    } label: {
                        Label("Clean Now", systemImage: "trash")
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
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Scan Results", icon: "list.bullet.clipboard")

                    HStack(spacing: 16) {
                        MetricStrip(items: [
                            ("Categories", "\(model.cleanCategories.count)"),
                            ("Reclaimable", model.cleanTotalSize)
                        ])
                    }

                    ForEach(model.cleanCategories) { cat in
                        HStack(spacing: 12) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(cat.color)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.name)
                                    .font(.system(size: 13, weight: .medium))
                                if !cat.detail.isEmpty {
                                    Text(cat.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(cat.size)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(cat.size == "--" ? .secondary : .primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
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
    }
}

struct CleanCategory: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let detail: String
    let icon: String
    let color: Color
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
