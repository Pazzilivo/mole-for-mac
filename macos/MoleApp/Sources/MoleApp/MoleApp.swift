import SwiftUI

@main
struct MoleDesktopApp: App {
    @StateObject private var model = MoleAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 680)
                .task {
                    model.checkFullDiskAccess()
                    if !model.hasFullDiskAccess {
                        model.requestAdmin()
                    } else {
                        await model.refreshDashboard()
                    }
                    Task { await model.checkForUpdates() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh") {
                    Task { await model.refreshDashboard() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsPane()
                .environmentObject(model)
                .frame(width: 560)
        }
    }
}

