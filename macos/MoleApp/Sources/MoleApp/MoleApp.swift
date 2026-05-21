import SwiftUI

@main
struct MoleDesktopApp: App {
    @StateObject private var rootModel = RootModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(rootModel.statusVM)
                .environmentObject(rootModel.uninstallVM)
                .environmentObject(rootModel.cleanVM)
                .environmentObject(rootModel.analyzeVM)
                .environmentObject(rootModel)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    rootModel.statusVM.checkFullDiskAccess()
                    await rootModel.refreshDashboard()
                    Task { await rootModel.checkForUpdates() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh") {
                    Task { await rootModel.refreshDashboard() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsPane()
                .environmentObject(rootModel)
                .frame(width: 560)
        }
    }
}
