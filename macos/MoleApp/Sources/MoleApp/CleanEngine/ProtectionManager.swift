import Foundation

/// Thread-sensitive app and system protection management
actor ProtectionManager {
    // MARK: - Protected Bundle Patterns
    private static let systemCriticalBundles: Set<String> = [
        // Core system applications
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.Safari",
        "com.apple.mail",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.Settings*",
        "com.apple.controlcenter*",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.apple.Preview",
        "com.apple.TextEdit",
        "com.apple.Notes",
        "com.apple.reminders",
        "com.apple.iCal",
        "com.apple.AddressBook",
        "com.apple.Photos",
        "com.apple.AppStore",
        "com.apple.calculator",
        "com.apple.Dictionary",
        "com.apple.ScreenSharing",
        "com.apple.ActivityMonitor",
        "com.apple.Console",
        "com.apple.DiskUtility",
        "com.apple.KeychainAccess",
        "com.apple.Terminal",
        "com.apple.ScriptEditor2",
        "com.apple.VoiceOverUtility",
        "com.apple.BluetoothFileExchange",
        "com.apple.print.PrinterProxy",
        "com.apple.systempreferences*",
        "com.apple.SystemProfiler",
        "com.apple.FontBook",
        "com.apple.ColorSyncUtility",
        "com.apple.audio.AudioMIDISetup",
        "com.apple.DirectoryUtility",
        "com.apple.NetworkUtility",
        "com.apple.exposelauncher",
        "com.apple.MigrateAssistant",
        "com.apple.RAIDUtility",
        "com.apple.BootCampAssistant",

        // System services and daemons
        "com.apple.SecurityAgent",
        "com.apple.CoreServices*",
        "com.apple.SystemUIServer",
        "com.apple.backgroundtaskmanagement*",
        "com.apple.loginitems*",
        "com.apple.sharedfilelist*",
        "com.apple.sfl*",
        "com.apple.coreservices*",
        "com.apple.metadata*",
        "com.apple.MobileSoftwareUpdate*",
        "com.apple.SoftwareUpdate*",
        "com.apple.installer*",
        "com.apple.frameworks*",
        "com.apple.security*",
        "com.apple.keychain*",
        "com.apple.trustd*",
        "com.apple.securityd*",
        "com.apple.cloudd*",
        "com.apple.iCloud*",
        "com.apple.WiFi*",
        "com.apple.airport*",
        "com.apple.Bluetooth*",

        // Input methods
        "com.apple.inputmethod.*",
        "com.apple.inputsource*",
        "com.apple.TextInput*",
        "com.apple.CharacterPicker*",
        "com.apple.PressAndHold*",

        // Legacy patterns
        "loginwindow",
        "dock",
        "systempreferences",
        "finder",
        "safari",
        "backgroundtaskmanagementagent",
        "keychain*",
        "security*",
        "bluetooth*",
        "wifi*",
        "network*",
        "tcc",
        "notification*",
        "accessibility*",
        "universalaccess*",
        "HIToolbox*",
        "textinput*",
        "TextInput*",
        "keyboard*",
        "Keyboard*",
        "inputsource*",
        "InputSource*",
        "keylayout*",
        "KeyLayout*",
        "GlobalPreferences",
        ".GlobalPreferences",
        "org.pqrs.Karabiner*",
        "org.cups.*"
    ]

    private static let dataProtectedBundles: Set<String> = [
        // Input Methods
        "com.tencent.inputmethod.QQInput",
        "com.sogou.inputmethod.*",
        "com.baidu.inputmethod.*",
        "com.googlecode.rimeime.*",
        "im.rime.*",

        // Password Managers
        "com.1password.*",
        "com.agilebits.*",
        "com.lastpass.*",
        "com.dashlane.*",
        "com.bitwarden.*",
        "com.keepassx.*",
        "org.keepassx.*",
        "org.keepassxc.*",
        "com.authy.*",
        "com.yubico.*",

        // IDEs & Editors
        "com.jetbrains.*",
        "JetBrains*",
        "com.microsoft.VSCode",
        "com.visualstudio.code.*",
        "com.sublimetext.*",
        "com.sublimehq.*",
        "com.microsoft.VSCodeInsiders",
        "com.apple.dt.Xcode",
        "com.coteditor.CotEditor",
        "com.macromates.TextMate",
        "com.panic.Nova",
        "abnerworks.Typora",

        // AI & LLM Tools
        "com.todesktop.*",
        "Cursor",
        "com.anthropic.claude*",
        "Claude",
        "com.openai.chat*",
        "ChatGPT",
        "com.openai.codex",
        "Codex",
        "codex-runtimes",
        "com.ollama.ollama",
        "Ollama",
        "com.lmstudio.lmstudio",
        "LM Studio",

        // Network Tools
        "com.clash.*",
        "ClashX*",
        "com.nssurge.surge-mac",
        "com.docker.*",
        "com.getpostman.*",
        "com.insomnia.*",

        // Communication
        "com.tencent.*",
        "com.alibaba.*",
        "us.zoom.xos",
        "com.microsoft.teams*",
        "com.slack.Slack",
        "org.telegram.desktop",
        "net.whatsapp.Whatsapp",

        // Cloud & Storage
        "com.dropbox.*",
        "ws.agile.*",
        "com.backblaze.*",
        "com.box.desktop*",
        "com.microsoft.OneDrive*",
        "com.google.GoogleDrive",
        "com.apple.bird",
        "com.apple.CloudDocs*",

        // Developer Tools
        "com.github.GitHubDesktop",
        "com.sublimemerge",
        "com.torusknot.SourceTreeNotMAS",
        "com.git-tower.Tower*",
        "com.gitfox.GitFox",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "com.hyper.Hyper",

        // Design & Creative
        "com.adobe.*",
        "com.bohemiancoding.*",
        "com.figma.*",
        "com.sketchup.*",
        "com.autodesk.*",
        "com.native-instruments.*",
        "com.fabfilter.*",

        // System Utilities
        "com.nektony.*",
        "com.macpaw.*",
        "com.freemacsoft.AppCleaner",
        "com.omnigroup.omnidisksweeper",
        "com.daisydiskapp.*",
        "com.tunabellysoftware.*",
        "com.grandperspectiv.*",
        "com.binaryfruit.*",

        // Window Management
        "com.macitbetter.*",
        "com.hegenberg.*",
        "com.manytricks.*",
        "com.divisiblebyzero.*",
        "com.koingdev.*",
        "com.if.Amphetamine",
        "com.lwouis.alt-tab-macos",
        "com.amethyst.Amethyst",
        "com.knollsoft.Rectangle",
        "com.surteesstudios.Bartender",

        // Launchers & Automation
        "com.runningwithcrayons.Alfred",
        "com.raycast.macos",
        "com.blacktree.Quicksilver",
        "com.stairways.keyboardmaestro.*",
        "org.pqrs.Karabiner-Elements",
        "com.apple.Automator",

        // Note-Taking
        "com.bear-writer.*",
        "com.typora.*",
        "com.ulyssesapp.*",
        "notion.id",
        "md.obsidian",
        "com.logseq.logseq",
        "com.evernote.Evernote",
        "com.onenote.mac",
        "com.omnigroup.OmniOutliner*",
        "net.shinyfrog.bear",

        // Task Management
        "com.omnigroup.OmniFocus*",
        "com.culturedcode.*",
        "com.todoist.*",
        "com.any.do.*",
        "com.ticktick.*",
        "com.microsoft.to-do",
        "com.trello.trello",
        "com.asana.nativeapp",
        "com.clickup.*",
        "com.monday.desktop",
        "com.airtable.airtable",
        "com.linear.linear"
    ]

    // Fast patterns for cleanup operations
    private static let fastProtectionPatterns: Set<String> = [
        "com.apple.*",
        "loginwindow",
        "dock",
        "systempreferences",
        "finder",
        "safari",
        "backgroundtaskmanagement*",
        "keychain*",
        "security*",
        "bluetooth*",
        "wifi*",
        "network*",
        "tcc",
        "notification*",
        "accessibility*",
        "universalaccess*",
        "HIToolbox*",
        "textinput*",
        "TextInput*",
        "keyboard*",
        "Keyboard*",
        "inputsource*",
        "InputSource*",
        "keylayout*",
        "KeyLayout*",
        "GlobalPreferences",
        ".GlobalPreferences",
        "org.pqrs.Karabiner*",
        "org.cups.*"
    ]

    // MARK: - Protected Path Patterns
    private static let protectedPathPatterns: Set<String> = [
        // System-critical caches
        "*com.apple.systempreferences.cache*",
        "*com.apple.Settings.cache*",
        "*com.apple.controlcenter.cache*",
        "*com.apple.finder.cache*",
        "*com.apple.dock.cache*",

        // System containers
        "*/Library/Containers/com.apple.Settings*",
        "*/Library/Containers/com.apple.SystemSettings*",
        "*/Library/Containers/com.apple.controlcenter*",
        "*/Library/Group Containers/com.apple.systempreferences*",
        "*/Library/Group Containers/com.apple.Settings*",
        "*/com.apple.sharedfilelist/*com.apple.Settings*",
        "*/com.apple.sharedfilelist/*com.apple.SystemSettings*",
        "*/com.apple.sharedfilelist/*systempreferences*",

        // Critical preferences
        "*/Library/Preferences/com.apple.dock.plist",
        "*/Library/Preferences/com.apple.finder.plist",

        // Mole's own runtime logs
        "*/Library/Logs/mole",
        "*/Library/Logs/mole/*",
        "*/Library/Logs/mole/*",

        // Network configurations
        "*/ByHost/com.apple.bluetooth.*",
        "*/ByHost/com.apple.wifi.*",
        "*/Library/Preferences/com.apple.networkextension*.plist",

        // iCloud and user data
        "*/Library/Mobile Documents*",
        "*/Mobile Documents*",

        // High-risk cleanup paths
        "*/Library/Accounts",
        "*/Library/Accounts/*",
        "*/Library/Keychains",
        "*/Library/Keychains/*",
        "*/Library/Mail",
        "*/Library/Mail/*",
        "*/Library/Calendars",
        "*/Library/Contacts",
        "*/Library/Contacts/*",

        // Audio plug-ins and professional software
        "/Library/Audio/Plug-Ins/Components*",
        "/Library/Audio/Plug-Ins/VST*",
        "/Library/Audio/Plug-Ins/VST3*",
        "*/Library/Application Support/iZotope*",
        "*/Library/Application Support/LaserSoft Imaging*",
        "*/Library/Preferences/com.native-instruments*",
        "*/Library/Preferences/com.avid.mediacomposer*.plist",
        "*/Library/Preferences/com.fabfilter.*",
        "*/Library/Preferences/com.paceap.*.plist",
        "/private/var/folders/*/C/com.native-instruments*",
        "/private/var/folders/*/C/com.avid.mediacomposer*",
        "/private/var/folders/*/C/com.paceap.eden.iLokLicenseManager*",

        // Protected caches
        "*/Library/Caches/ms-playwright*",
        "*/Library/Caches/app.cotypist.Cotypist*",
        "*/Library/Caches/com.displaylink.DisplayLinkUserAgent*",
        "*/Library/Caches/com.lasersoft-imaging.SilverFast*",
        "*/Library/Caches/Adobe *",
        "*/Library/Caches/* Adobe*",
        "*/Library/Caches/com.apple.containermanagerd*",
        "*/Library/Caches/com.apple.homed*",
        "*/Library/Caches/com.apple.ap.adprivacyd*",
        "*/Library/Caches/FamilyCircle*",
        "*/Library/Caches/com.apple.HomeKit*",
        "*/Library/Caches/com.apple.WorkflowKit.BackgroundShortcutRunner.ShortcutsSandboxCache*",
        "*/Library/Caches/com.apple.siriactionsd.ShortcutsSandboxCache*",

        // CoreAudio and audio subsystem
        "*com.apple.coreaudio*",
        "*com.apple.audio.*",
        "*coreaudiod*"
    ]

    // MARK: - Protection Methods
    func isCriticalSystemComponent(_ bundleID: String) -> Bool {
        let lowerBundleID = bundleID.lowercased()

        // Fast path: check against critical patterns
        for pattern in Self.fastProtectionPatterns {
            if matchesPattern(lowerBundleID, pattern: pattern.lowercased()) {
                return true
            }
        }

        return false
    }

    func shouldProtectFromUninstall(_ bundleID: String) -> Bool {
        // Check system critical bundles
        if matchesAnyPattern(bundleID, patterns: Self.systemCriticalBundles) {
            return true
        }

        return false
    }

    func shouldProtectData(_ bundleID: String) -> Bool {
        // Check system critical bundles
        if matchesAnyPattern(bundleID, patterns: Self.systemCriticalBundles) {
            return true
        }

        // Check data protected bundles
        if matchesAnyPattern(bundleID, patterns: Self.dataProtectedBundles) {
            return true
        }

        return false
    }

    func shouldProtectPath(_ path: String, mode: CleanMode = .standard) -> Bool {
        // 1. Check keyword-based matching for system components
        let lowercasedPath = path.lowercased()
        if lowercasedPath.contains("systemsettings") ||
           lowercasedPath.contains("systempreferences") ||
           lowercasedPath.contains("controlcenter") {
            return true
        }

        // 2. Protect caches critical for system UI rendering
        if containsProtectedCachePath(path) {
            return true
        }

        // 3. Extract bundle ID from sandbox paths
        if let bundleID = extractBundleID(from: path) {
            // Cache and tmp directories inside containers are regenerable
            if path.contains("/Data/Library/Caches/") || path.contains("/Data/tmp/") {
                return false
            }

            // In cleanup mode, protect data-protected bundles
            if mode != .aggressive && shouldProtectData(bundleID) {
                return true
            }
        }

        // 4. Check specific hardcoded critical patterns
        if containsCriticalPattern(path) {
            return true
        }

        // 5. Protect critical preference files and user data
        if containsProtectedUserPath(path) {
            return true
        }

        // 6. Match full path against protected patterns
        if matchesProtectedPathPattern(path) {
            return true
        }

        // 7. Check filename against protected patterns (in non-aggressive mode)
        if mode != .aggressive {
            let filename = (path as NSString).lastPathComponent
            if shouldProtectData(filename) {
                return true
            }
        }

        return false
    }

    // MARK: - Private Helpers
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        let regexPattern = convertWildcardToRegex(pattern)
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else {
            return false
        }

        let range = NSRange(location: 0, length: string.utf16.count)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }

    private func matchesAnyPattern(_ string: String, patterns: Set<String>) -> Bool {
        for pattern in patterns {
            if matchesPattern(string, pattern: pattern) {
                return true
            }
        }
        return false
    }

    private func convertWildcardToRegex(_ pattern: String) -> String {
        var regex = NSRegularExpression.escapedPattern(for: pattern)
        regex = regex.replacingOccurrences(of: "\\*", with: ".*")
        regex = regex.replacingOccurrences(of: "\\?", with: ".")
        return "^" + regex + "$"
    }

    private func extractBundleID(from path: String) -> String? {
        // Matches: .../Library/Containers/bundle.id/...
        // Matches: .../Library/Group Containers/group.id/...
        let containerPattern = "/Library/Containers/([^/]+)"
        let groupContainerPattern = "/Library/Group Containers/([^/]+)"

        if let range = path.range(of: containerPattern, options: .regularExpression) {
            let afterPattern = path[range.upperBound...]
            if let endRange = afterPattern.range(of: "/") {
                return String(afterPattern[..<endRange.lowerBound])
            }
        }

        if let range = path.range(of: groupContainerPattern, options: .regularExpression) {
            let afterPattern = path[range.upperBound...]
            if let endRange = afterPattern.range(of: "/") {
                return String(afterPattern[..<endRange.lowerBound])
            }
        }

        return nil
    }

    private func containsProtectedCachePath(_ path: String) -> Bool {
        let lowercasedPath = path.lowercased()

        for pattern in Self.protectedPathPatterns {
            let lowercasedPattern = pattern.lowercased()
            if matchesPattern(lowercasedPath, pattern: lowercasedPattern) {
                return true
            }
        }

        return false
    }

    private func containsCriticalPattern(_ path: String) -> Bool {
        let criticalPatterns = [
            "com.apple.Settings*",
            "com.apple.SystemSettings*",
            "com.apple.controlcenter*",
            "com.apple.finder*",
            "com.apple.dock*"
        ]

        for pattern in criticalPatterns {
            if matchesPattern(path.lowercased(), pattern: pattern.lowercased()) {
                return true
            }
        }

        return false
    }

    private func containsProtectedUserPath(_ path: String) -> Bool {
        let protectedPaths = [
            "*/Library/Preferences/com.apple.dock.plist",
            "*/Library/Preferences/com.apple.finder.plist",
            "*/Library/Logs/mole",
            "*/Library/Logs/mole/",
            "*/Library/Logs/mole/*",
            "*/ByHost/com.apple.bluetooth.*",
            "*/ByHost/com.apple.wifi.*",
            "*/Library/Preferences/com.apple.networkextension*.plist",
            "*/Library/Mobile Documents*",
            "*/Mobile Documents*",
            "*/Library/Accounts",
            "*/Library/Accounts/*",
            "*/Library/Keychains",
            "*/Library/Keychains/*",
            "*/Library/Mail",
            "*/Library/Mail/*",
            "*/Library/Calendars",
            "*/Library/Contacts",
            "*/Library/Contacts/*"
        ]

        for pattern in protectedPaths {
            if matchesPattern(path, pattern: pattern) {
                return true
            }
        }

        return false
    }

    private func matchesProtectedPathPattern(_ path: String) -> Bool {
        for pattern in Self.protectedPathPatterns {
            if matchesPattern(path, pattern: pattern) {
                return true
            }
        }

        return false
    }

    // MARK: - Public Utilities
    func getProtectedBundles(for mode: CleanMode = .standard) -> Set<String> {
        var protected = Self.systemCriticalBundles

        if mode != .aggressive {
            protected.formUnion(Self.dataProtectedBundles)
        }

        return protected
    }

    func getProtectedPaths() -> Set<String> {
        return Self.protectedPathPatterns
    }

    func getProtectionLevel(for path: String) -> RiskLevel {
        if shouldProtectPath(path, mode: .aggressive) {
            return .high
        } else if shouldProtectPath(path, mode: .standard) {
            return .medium
        } else {
            return .low
        }
    }
}