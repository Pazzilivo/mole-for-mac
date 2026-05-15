import Foundation

/// Directory classification rules for scanning and cleaning
struct DirectoryRules {

    // MARK: - Fold Directories
    /// Directories to fold (scan with du instead of full traversal)
    static let foldDirs: Set<String> = [
        // VCS
        ".git", ".svn", ".hg",

        // JavaScript/Node
        "node_modules", ".npm", "_npx", "_cacache", "_logs", "_locks", "_quick",
        "_libvips", "_prebuilds", "_update-notifier-last-checked", ".yarn", ".pnpm-store",
        ".next", ".nuxt", "bower_components", ".vite", ".turbo", ".parcel-cache",
        ".nx", ".rush", "tnpm", ".tnpm", ".bun", ".deno",

        // Python
        "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
        "venv", ".venv", "virtualenv", ".tox", "site-packages", ".eggs", "*.egg-info",
        ".pyenv", ".poetry", ".pip", ".pipx",

        // Ruby/Go/PHP (vendor), Java/Kotlin/Scala/Rust (target)
        "vendor", ".bundle", "gems", ".rbenv", "target", ".gradle", ".m2", ".ivy2",
        "out", "pkg", "composer.phar", ".composer", ".cargo",

        // Build outputs
        "build", "dist", ".output", "coverage", ".coverage",

        // IDE
        ".idea", ".vscode", ".vs", ".fleet",

        // Cache directories
        ".cache", "__MACOSX", ".DS_Store", ".Trash", "Caches", ".Spotlight-V100",
        ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems", "$RECYCLE.BIN",
        ".temp", ".tmp", "_temp", "_tmp", ".Homebrew", ".rustup", ".sdkman", ".nvm",

        // macOS
        "Application Scripts", "Saved Application State",

        // iCloud
        "Mobile Documents",

        // Containers
        ".docker", ".containerd",

        // Mobile development
        "Pods", "DerivedData", ".build", "xcuserdata", "Carthage", ".dart_tool",

        // Web frameworks
        ".angular", ".svelte-kit", ".astro", ".solid",

        // Databases
        ".mysql", ".postgres", "mongodb",

        // Other
        ".terraform", ".vagrant", "tmp", "temp",
    ]

    // MARK: - Skip System Directories
    /// System directories to skip at root level
    static let skipSystemDirs: [String: Bool] = [
        "dev": true,
        "tmp": true,
        "private": true,
        "cores": true,
        "net": true,
        "home": true,
        "System": true,
        "sbin": true,
        "bin": true,
        "etc": true,
        "var": true,
        "opt": false,      // opt may be useful
        "usr": false,      // usr may be useful
        "Volumes": true,
        "Network": true,
        ".vol": true,
        ".Spotlight-V100": true,
        ".fseventsd": true,
        ".DocumentRevisions-V100": true,
        ".TemporaryItems": true,
        ".MobileBackups": true,
    ]

    // MARK: - Default Skip Directories
    /// Directories to skip in all locations
    static let defaultSkipDirs: Set<String> = [
        "nfs", "PHD", "Permissions",

        // Virtualization/Container mounts
        "OrbStack",        // OrbStack NFS mounts
        "Colima",          // Colima VM mounts
        "Parallels",       // Parallels Desktop VMs
        "VMware Fusion",   // VMware Fusion VMs
        "VirtualBox VMs",  // VirtualBox VMs
        "Rancher Desktop", // Rancher Desktop mounts
        ".lima",           // Lima VM mounts
        ".colima",         // Colima config/mounts
        ".orbstack",       // OrbStack config/mounts
    ]

    // MARK: - Skip Extensions
    /// File extensions to skip in large file tracking
    static let skipExtensions: Set<String> = [
        ".go", ".js", ".ts", ".tsx", ".jsx", ".json", ".md", ".txt",
        ".yml", ".yaml", ".xml", ".html", ".css", ".scss", ".sass", ".less",
        ".py", ".rb", ".java", ".kt", ".rs", ".swift", ".m", ".mm",
        ".c", ".cpp", ".h", ".hpp", ".cs", ".sql", ".db", ".lock",
        ".gradle", ".mjs", ".cjs", ".coffee", ".dart", ".svelte", ".vue",
        ".nim", ".hx",
    ]

    // MARK: - Overview du Ignore Names
    /// Directory names to ignore during overview du scanning
    static let overviewDuIgnoreNames: Set<String> = [
        "Mobile Documents",  // iCloud Drive (can block du for tens of seconds)
    ]

    // MARK: - Project Dependency Directories
    /// Project dependency and build directories (safe to clean)
    static let projectDependencyDirs: Set<String> = [
        // JavaScript/Node
        "node_modules", "bower_components", ".yarn", ".pnpm-store",

        // Python
        "venv", ".venv", "virtualenv", "__pycache__", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", ".tox", ".eggs", "htmlcov", ".ipynb_checkpoints",

        // Ruby
        "vendor", ".bundle",

        // Java/Kotlin/Scala
        ".gradle", "out",

        // Build outputs
        "build", "dist", "target", ".next", ".nuxt", ".output",
        ".parcel-cache", ".turbo", ".vite", ".nx", "coverage", ".coverage", ".nyc_output",

        // Frontend framework outputs
        ".angular", ".svelte-kit", ".astro", ".docusaurus",

        // Apple dev
        "DerivedData", "Pods", ".build", "Carthage", ".dart_tool",

        // Other tools
        ".terraform",
    ]

    // MARK: - Mo Clean Handled Fragments
    /// Path fragments that are already handled by mo clean
    static let moCleanHandledFragments: [String] = [
        "/Library/Caches/",
        "/Library/Logs/",
        "/Library/Saved Application State/",
        "/.Trash/",
        "/Library/DiagnosticReports/",
    ]
}