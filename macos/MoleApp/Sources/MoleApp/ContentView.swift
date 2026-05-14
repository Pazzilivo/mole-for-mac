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

struct OverviewPane: View {
    @EnvironmentObject private var model: MoleAppModel
    @Binding var selection: AppSection?

    var body: some View {
        Workspace(title: "Overview", subtitle: "System health and the next maintenance actions.") {
            if !model.hasFullDiskAccess {
                FullDiskAccessBanner()
            }

            if case let .failed(message) = model.statusState {
                ErrorBanner(message: message)
            }

            QuickActions(selection: $selection)

            if let status = model.status {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top, spacing: 36) {
                        HealthBlock(status: status)
                        MetricStack(status: status)
                    }

                    Divider()

                    DiskList(disks: status.disks ?? [])

                    Divider()

                    ProcessList(processes: status.topProcesses ?? [])
                }
            } else if model.statusState == .loading {
                LoadingView(title: "Collecting metrics")
            } else {
                EmptyState(title: "No status yet", detail: "Refresh to load CPU, memory, disk, and process data.")
            }
        }
    }
}

struct QuickActions: View {
    @Binding var selection: AppSection?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                selection = .clean
            } label: {
                Label("Scan Cleanup", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)

            Button {
                selection = .analyze
            } label: {
                Label("Analyze Disk", systemImage: "externaldrive")
            }

            Button {
                selection = .uninstall
            } label: {
                Label("Review Apps", systemImage: "trash")
            }

            Button {
                selection = .optimize
            } label: {
                Label("Optimize", systemImage: "wrench.and.screwdriver")
            }
        }
    }
}

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

                if model.analyzeState == .loading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if case let .failed(message) = model.analyzeState {
                ErrorBanner(message: message)
            }

            if let analysis = model.analysis {
                VStack(alignment: .leading, spacing: 16) {
                    Text(analysis.path)
                        .font(.callout)
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
            } else if model.analyzeState == .idle {
                EmptyState(title: "Ready to scan", detail: "The first pass uses `mo analyze --json` against your home folder.")
            }
        }
    }
}

struct UninstallPane: View {
    @EnvironmentObject private var model: MoleAppModel
    @State private var query = ""

    private var filteredApps: [AppEntry] {
        guard !query.isEmpty else { return model.apps }
        return model.apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        Workspace(title: "Uninstall", subtitle: "List installed apps and prepare preview-first removal flows.") {
            HStack {
                TextField("Search apps", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Button {
                    Task { await model.refreshApps() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }

            if case let .failed(message) = model.appsState {
                ErrorBanner(message: message)
            }

            Table(filteredApps) {
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

            Text("Destructive uninstall actions are intentionally held back until JSON preview and apply commands are added.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsPane: View {
    @EnvironmentObject private var model: MoleAppModel

    var body: some View {
        Workspace(title: "Settings", subtitle: "Runtime, command line access, and local diagnostics.") {
            VStack(alignment: .leading, spacing: 18) {
                LabeledContent("Bundled runtime") {
                    Text(model.runtime.root.path)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Runtime checks")
                        .font(.headline)
                    ForEach(model.runtime.runtimeChecks()) { check in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: check.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.isAvailable ? .green : .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title)
                                Text(check.detail)
                                    .font(.caption)
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

                Text("The app always uses its bundled runtime. Installing `mo` only adds optional terminal access for this user.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                ActivityList(lines: model.activity)
            }
        }
    }
}

struct Workspace<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 34, weight: .semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HealthBlock: View {
    let status: StatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health")
                .font(.headline)
            Text("\(status.healthScore ?? 0)")
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(status.healthScoreMsg ?? "System health")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(status.hardware?.model ?? status.host ?? "This Mac")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(width: 220, alignment: .leading)
    }
}

struct MetricStack: View {
    let status: StatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MeterRow(title: "CPU", value: status.cpu?.usage, detail: loadText)
            MeterRow(title: "Memory", value: status.memory?.usedPercent, detail: memoryText)
            if let disk = status.disks?.first {
                MeterRow(title: "Disk", value: disk.usedPercent, detail: "\(ByteFormat.string(disk.used)) used of \(ByteFormat.string(disk.total))")
            }
        }
        .frame(maxWidth: 520)
    }

    private var loadText: String {
        guard let cpu = status.cpu else { return "Unknown load" }
        return "Load \(format(cpu.load1)) / \(format(cpu.load5)) / \(format(cpu.load15))"
    }

    private var memoryText: String {
        "\(ByteFormat.string(status.memory?.used)) used of \(ByteFormat.string(status.memory?.total))"
    }
}

struct MeterRow: View {
    let title: String
    let value: Double?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "Unknown")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: clamped(value), total: 100)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func clamped(_ value: Double?) -> Double {
        min(max(value ?? 0, 0), 100)
    }
}

struct DiskList: View {
    let disks: [DiskInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disks")
                .font(.headline)

            ForEach(disks.prefix(5)) { disk in
                HStack {
                    VStack(alignment: .leading) {
                        Text(disk.mount ?? disk.device ?? "Disk")
                        Text(disk.external == true ? "External" : "Internal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(ByteFormat.string(disk.used)) / \(ByteFormat.string(disk.total))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ProcessList: View {
    let processes: [TopProcess]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Processes")
                .font(.headline)

            ForEach(processes.prefix(6)) { process in
                HStack {
                    Text(process.name ?? process.command ?? "Process")
                    Spacer()
                    Text("\(format(process.cpu))% CPU")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct MetricStrip: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 28) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.1)
                        .font(.title3.monospacedDigit())
                }
            }
        }
    }
}

struct ActivityList: View {
    let lines: [ActivityLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity")
                .font(.headline)
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title)
                        .foregroundStyle(line.isError ? .red : .primary)
                    Text(line.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
    }
}

struct FullDiskAccessBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Full Disk Access Required", systemImage: "lock.shield")
                .font(.headline)

            Text("Mole needs Full Disk Access to scan system caches, app data, and disk usage. Without it, you may see repeated permission prompts or missing data.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("How to grant access:")
                    .font(.callout.weight(.medium))
                Text("1. Open System Settings > Privacy & Security > Full Disk Access")
                Text("2. Click the + button and add Mole.app")
                Text("3. Restart Mole")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            } label: {
                Label("Open System Settings", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LoadingView: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

struct EmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 32)
    }
}

private func format(_ value: Double?) -> String {
    guard let value else { return "0.0" }
    return String(format: "%.1f", value)
}
