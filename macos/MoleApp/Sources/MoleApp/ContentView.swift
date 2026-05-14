import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case clean = "Clean"
    case uninstall = "Uninstall"
    case analyze = "Analyze"
    case optimize = "Optimize"
    case artifacts = "Artifacts"
    case logs = "Logs"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .clean: return "sparkles"
        case .uninstall: return "trash"
        case .analyze: return "externaldrive"
        case .optimize: return "wrench.and.screwdriver"
        case .artifacts: return "shippingbox"
        case .logs: return "doc.text.magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: MoleAppModel
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Mole")
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await model.refreshDashboard() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
            }
        } detail: {
            switch selection ?? .overview {
            case .overview:
                OverviewPane(selection: $selection)
            case .clean:
                CleanPane()
            case .uninstall:
                UninstallPane()
            case .analyze:
                AnalyzePane()
            case .optimize:
                OptimizePane()
            case .artifacts:
                ArtifactsPane()
            case .logs:
                LogsPane()
            case .settings:
                SettingsPane()
            }
        }
    }
}

// MARK: - Overview

struct OverviewPane: View {
    @EnvironmentObject private var model: MoleAppModel
    @Binding var selection: AppSection?

    var body: some View {
        Workspace(title: "Overview", subtitle: "System health at a glance.") {
            VStack(spacing: 20) {
                if model.updateState == .ready {
                    UpdateBanner(version: model.latestVersion) {
                        Task { await model.performUpdate() }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !model.hasFullDiskAccess {
                    FullDiskAccessBanner()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if case let .failed(message) = model.statusState {
                    ErrorBanner(message: message)
                }

                QuickActions(selection: $selection)
            }

            if let status = model.status {
                VStack(spacing: 24) {
                    HealthDashboard(status: status)
                    DiskList(disks: status.disks ?? [])
                    ProcessList(processes: status.topProcesses ?? [])
                }
                .transition(.opacity)
            } else if model.statusState == .loading {
                LoadingView(title: "Collecting system metrics...")
            } else {
                EmptyState(
                    icon: "gauge.with.dots.needle.67percent",
                    title: "No status data",
                    detail: "Click the refresh button or press ⌘R to load system metrics."
                )
            }
        }
    }
}

// MARK: - Quick Actions

struct QuickActions: View {
    @Binding var selection: AppSection?

    var body: some View {
        HStack(spacing: 10) {
            ActionPill(title: "Scan Cleanup", icon: "sparkles", isPrimary: true) {
                selection = .clean
            }
            ActionPill(title: "Analyze Disk", icon: "externaldrive", isPrimary: false) {
                selection = .analyze
            }
            ActionPill(title: "Review Apps", icon: "trash", isPrimary: false) {
                selection = .uninstall
            }
            ActionPill(title: "Optimize", icon: "wrench.and.screwdriver", isPrimary: false) {
                selection = .optimize
            }
        }
    }
}

struct ActionPill: View {
    let title: String
    let icon: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.borderedProminent)
        .tint(isPrimary ? .accentColor : .clear)
        .foregroundStyle(isPrimary ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Health Dashboard

struct HealthDashboard: View {
    let status: StatusSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            HealthScoreCard(status: status)
            MetricCards(status: status)
        }
    }
}

struct HealthScoreCard: View {
    let status: StatusSnapshot
    private let score = 72

    var scoreColor: Color {
        let s = status.healthScore ?? 0
        if s >= 80 { return .green }
        if s >= 60 { return .orange }
        return .red
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: Double(status.healthScore ?? 0) / 100.0)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: status.healthScore)
                Text("\(status.healthScore ?? 0)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .frame(width: 100, height: 100)

            VStack(spacing: 4) {
                Text(status.healthScoreMsg ?? "System Health")
                    .font(.system(size: 13, weight: .semibold))
                Text(status.hardware?.model ?? status.host ?? "This Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let os = status.hardware?.osVersion {
                    Text(os)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MetricCards: View {
    let status: StatusSnapshot

    var body: some View {
        VStack(spacing: 10) {
            MetricCardRow(
                icon: "cpu",
                title: "CPU",
                value: status.cpu?.usage.map { "\(Int($0.rounded()))%" } ?? "--",
                detail: loadText,
                progress: status.cpu?.usage ?? 0,
                color: .blue
            )
            MetricCardRow(
                icon: "memorychip",
                title: "Memory",
                value: status.memory?.usedPercent.map { "\(Int($0.rounded()))%" } ?? "--",
                detail: memoryText,
                progress: status.memory?.usedPercent ?? 0,
                color: .orange
            )
            if let disk = status.disks?.first {
                MetricCardRow(
                    icon: "internaldrive",
                    title: "Disk",
                    value: disk.usedPercent.map { "\(Int($0.rounded()))%" } ?? "--",
                    detail: "\(ByteFormat.string(disk.used)) of \(ByteFormat.string(disk.total))",
                    progress: disk.usedPercent ?? 0,
                    color: .purple
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var loadText: String {
        guard let cpu = status.cpu else { return "Unknown load" }
        return "Load \(format(cpu.load1)) / \(format(cpu.load5)) / \(format(cpu.load15))"
    }

    private var memoryText: String {
        "\(ByteFormat.string(status.memory?.used)) of \(ByteFormat.string(status.memory?.total))"
    }
}

struct MetricCardRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let progress: Double
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                ProgressView(value: min(max(progress, 0), 100), total: 100)
                    .tint(color)
                    .animation(.easeOut(duration: 0.6), value: progress)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Disk & Process Lists

struct DiskList: View {
    let disks: [DiskInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Disks", icon: "internaldrive")

            ForEach(disks.prefix(5)) { disk in
                HStack(spacing: 12) {
                    Image(systemName: disk.external == true ? "externaldrive" : "internaldrive")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(disk.mount ?? disk.device ?? "Disk")
                            .font(.system(size: 13, weight: .medium))
                        Text(disk.external == true ? "External" : "Internal")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text("\(ByteFormat.string(disk.used)) / \(ByteFormat.string(disk.total))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

struct ProcessList: View {
    let processes: [TopProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Top Processes", icon: "chart.bar")

            ForEach(processes.prefix(6)) { process in
                HStack(spacing: 12) {
                    Text(process.name ?? process.command ?? "Process")
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    Text("\(format(process.cpu))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(cpuColor(process.cpu))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func cpuColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v > 50 { return .red }
        if v > 25 { return .orange }
        return .secondary
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .textCase(.uppercase)
    }
}

// MARK: - Analyze

struct AnalyzePane: View {
    @EnvironmentObject private var model: MoleAppModel

    var body: some View {
        Workspace(title: "Analyze", subtitle: "Inspect disk usage before removing anything.") {
            HStack {
                Button {
                    Task { await model.analyzeHome() }
                } label: {
                    Label("Analyze Home", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(model.analyzeState == .loading)

                if model.analyzeState == .loading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.analyzeProgress.isEmpty ? "Starting analysis..." : model.analyzeProgress)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .animation(.easeInOut(duration: 0.3), value: model.analyzeProgress)
                    }
                }
            }

            if case let .failed(message) = model.analyzeState {
                ErrorBanner(message: message)
            }

            if let analysis = model.analysis {
                VStack(alignment: .leading, spacing: 16) {
                    Text(analysis.path)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    MetricStrip(items: [
                        ("Total", ByteFormat.string(analysis.totalSize)),
                        ("Files", analysis.totalFiles.map(String.init) ?? "Unknown"),
                        ("Entries", String(analysis.entries.count))
                    ])

                    Table(analysis.entries.prefix(20).map { $0 }) {
                        TableColumn("Name", value: \.name)
                        TableColumn("Size") { entry in
                            Text(ByteFormat.string(entry.size))
                        }
                        TableColumn("Kind") { entry in
                            Text(entry.isDir ? "Folder" : "File")
                        }
                    }
                    .frame(minHeight: 360)
                }
                .transition(.opacity)
            } else if model.analyzeState == .idle {
                EmptyState(
                    icon: "magnifyingglass",
                    title: "Ready to scan",
                    detail: "Click Analyze Home to scan your home folder disk usage."
                )
            }
        }
    }
}

// MARK: - Uninstall

struct UninstallPane: View {
    @EnvironmentObject private var model: MoleAppModel
    @State private var query = ""
    @State private var selectedApp: AppEntry?
    @State private var showConfirm = false

    private var filteredApps: [AppEntry] {
        guard !query.isEmpty else { return model.apps }
        return model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        Workspace(title: "Uninstall", subtitle: "Remove applications and their leftover files.") {
            HStack {
                TextField("Search apps...", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Button {
                    Task { await model.refreshApps() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan")

                Spacer()

                if let app = selectedApp {
                    Button {
                        showConfirm = true
                    } label: {
                        Label("Uninstall \(app.name)", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(model.uninstallState == .loading)
                }
            }

            if case let .failed(message) = model.uninstallState {
                ErrorBanner(message: message)
            }

            if model.uninstallState == .loading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.uninstallProgress.isEmpty ? "Uninstalling..." : model.uninstallProgress)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Table(filteredApps, selection: Binding(
                get: { selectedApp?.id },
                set: { newID in selectedApp = filteredApps.first(where: { $0.id == newID }) }
            )) {
                TableColumn("Name", value: \.name)
                TableColumn("Source") { app in
                    Text(app.source ?? "App")
                }
                TableColumn("Size") { app in
                    Text(app.size ?? "Unknown")
                }
                TableColumn("Bundle ID") { app in
                    Text(app.bundleID ?? "Unknown")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 440)
            .alert("Uninstall \(selectedApp?.name ?? "App")?", isPresented: $showConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Uninstall", role: .destructive) {
                    if let app = selectedApp {
                        Task { await model.uninstallApp(app) }
                    }
                }
            } message: {
                Text("This will move \(selectedApp?.name ?? "the app") and its data to Trash. This action can be undone from Finder.")
            }
        }
    }
}

// MARK: - Settings

struct SettingsPane: View {
    @EnvironmentObject private var model: MoleAppModel

    var body: some View {
        Workspace(title: "Settings", subtitle: "Runtime, command line access, and local diagnostics.") {
            VStack(alignment: .leading, spacing: 18) {
                // Updates section
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Updates", icon: "arrow.triangle.2.circlepath")

                    HStack(spacing: 12) {
                        Text("Current version: \(model.currentVersion)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        if model.updateState == .loading && model.latestVersion.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task { await model.checkForUpdates() }
                            } label: {
                                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(model.updateState == .loading)
                        }
                    }

                    if !model.latestVersion.isEmpty {
                        HStack(spacing: 12) {
                            Text("New version \(model.latestVersion) available")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.orange)

                            if model.updateState == .ready {
                                Button {
                                    Task { await model.performUpdate() }
                                } label: {
                                    Label("Update Now", systemImage: "arrow.down.circle")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        if !model.updateProgress.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    if model.updateState == .loading {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text(model.updateProgress)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                if model.updateDownloadPercent > 0 && model.updateDownloadPercent < 1 {
                                    ProgressView(value: model.updateDownloadPercent, total: 1.0)
                                        .tint(.accentColor)
                                }
                            }
                            .frame(maxWidth: 300)
                        }
                    }

                    if case let .failed(message) = model.updateState {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }

                Divider()

                LabeledContent("Bundled runtime") {
                    Text(model.runtime.root.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Runtime Checks", icon: "checklist")
                    ForEach(model.runtime.runtimeChecks()) { check in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: check.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.isAvailable ? .green : .orange)
                                .font(.system(size: 14))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(check.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Divider()

                Button {
                    model.installUserCLI()
                } label: {
                    Label("Install `mo` in ~/.local/bin", systemImage: "terminal")
                }

                Text("The app always uses its bundled runtime. Installing `mo` only adds optional terminal access.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Divider()

                ActivityList(lines: model.activity)
            }
        }
    }
}

// MARK: - Shared Components

struct Workspace<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MetricStrip: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 28) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(item.1)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ActivityList: View {
    let lines: [ActivityLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent Activity", icon: "clock")
            ForEach(lines) { line in
                HStack(spacing: 8) {
                    Image(systemName: line.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(line.isError ? .red : .green)
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(line.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(12)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct UpdateBanner: View {
    let version: String
    let onUpdate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
            Text("A new version (v\(version)) is available")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button("Update", action: onUpdate)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.15), lineWidth: 1))
    }
}

struct FullDiskAccessBanner: View {
    @EnvironmentObject private var model: MoleAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: model.isAdmin ? "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 16))
                    .foregroundStyle(model.isAdmin ? .green : .orange)
                Text(model.isAdmin ? "Admin Access Granted" : "Admin Access Required")
                    .font(.system(size: 14, weight: .semibold))
            }

            if model.isAdmin {
                Text("Mole is running with administrator privileges. All features are available.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                Text("Mole needs admin access to scan system caches, app data, and disk usage without repeated permission prompts.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        model.requestAdmin()
                    } label: {
                        Label("Authenticate as Admin", systemImage: "lock.open")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                    } label: {
                        Label("Or Grant Full Disk Access", systemImage: "gear")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(model.isAdmin ? Color.green.opacity(0.06) : Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.isAdmin ? Color.green.opacity(0.15) : Color.orange.opacity(0.15), lineWidth: 1))
    }
}

struct LoadingView: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 48)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String

    init(icon: String = "tray", title: String, detail: String) {
        self.icon = icon
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

private func format(_ value: Double?) -> String {
    guard let value else { return "0.0" }
    return String(format: "%.1f", value)
}
