import Foundation

enum AppListAdapter {
    static func convert(_ apps: [AppInfo]) -> [AppEntry] {
        apps.map { app in
            let sizeStr = ByteCountFormatter.string(fromByteCount: app.size, countStyle: .file)
            let source: String
            if app.isBrewCask {
                source = "homebrew"
            } else if app.isSystemApp {
                source = "system"
            } else {
                source = "local"
            }
            return AppEntry(
                name: app.name,
                bundleID: app.id,
                source: source,
                uninstallName: app.isBrewCask ? (app.brewCaskName ?? app.name) : app.name,
                path: app.path.path,
                size: sizeStr
            )
        }
    }
}
