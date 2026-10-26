//
//  DevModels.swift
//  Orbit
//

import Foundation

nonisolated enum DevGroup: String, CaseIterable, Identifiable, Sendable {
    case agents = "AI Apps, Agents & Editors"
    case xcode = "Xcode Junk"
    case brew = "Brew Cache"
    case node = "Node Cache"
    case docker = "Docker Cache"
    case buildTools = "Languages & Build Tools"
    case projects = "Project Build Artifacts"
    case deep = "Deep Cleanup: ~/.cache & Stale Installers"
    case systemJunk = "System Junk"
    case userCache = "User Cache"
    case mailFiles = "Mail Files"
    case leftovers = "Leftovers"
    var id: String { rawValue }

    static let developerGroups: [DevGroup] = [.agents, .xcode, .brew, .node, .docker, .buildTools, .projects, .deep]
    var isDeveloper: Bool { Self.developerGroups.contains(self) }

    var shortName: String {
        switch self {
        case .systemJunk: "System Junk"
        case .userCache: "User Cache"
        case .mailFiles: "Mail Files"
        case .leftovers: "Leftovers"
        case .buildTools: "Languages & Build Tools"
        case .agents: "AI Apps"
        case .xcode: "Xcode Junk"
        case .brew: "Brew Cache"
        case .node: "Node Cache"
        case .docker: "Docker Cache"
        case .projects: "Project Artifacts"
        case .deep: "Deep Cleanup"
        }
    }

    var subtitle: String {
        switch self {
        case .systemJunk: "Logs, crash reports and other diagnostic leftovers in your user account"
        case .userCache: "Per-app cache folders in ~/Library/Caches"
        case .mailFiles: "Attachments Mail saved when you opened them"
        case .leftovers: "Support files from apps that are no longer installed"
        case .buildTools: "Gradle, Maven, Python, Rust, Go and other language toolchain caches"
        case .agents: "Caches, logs and state from Claude, Cursor, Antigravity, Windsurf, VS Code, JetBrains and more"
        case .xcode: "DerivedData, device support, simulators and archives"
        case .brew: "Homebrew downloads and logs"
        case .node: "npm, Yarn, pnpm, Bun, Deno and Node tooling caches"
        case .docker: "Docker Desktop logs and caches. Container data is shown but never removed by Orbit"
        case .projects: "node_modules, build and target folders inside your projects"
        case .deep: "~/.cache tool folders and stale installers in Downloads: items Orbit can't fully verify"
        }
    }

    var symbol: String {
        switch self {
        case .systemJunk: "gearshape.fill"
        case .userCache: "externaldrive.fill"
        case .mailFiles: "envelope.fill"
        case .leftovers: "questionmark.folder"
        case .buildTools: "wrench.and.screwdriver.fill"
        case .agents: "cpu"
        case .xcode: "hammer.fill"
        case .brew: "mug.fill"
        case .node: "leaf.fill"
        case .docker: "shippingbox.fill"
        case .projects: "folder.badge.gearshape"
        case .deep: "magnifyingglass.circle"
        }
    }
}

nonisolated enum DevRisk: String, Sendable {
    /// Rebuilt or re-downloaded automatically by the tool.
    case regenerable = "Regenerable"
    /// May contain data that can't be recreated. Never selected by default.
    case caution = "Review carefully"
}

nonisolated struct DevItem: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let title: String
    let tool: String
    let group: DevGroup
    let risk: DevRisk
    let reason: String
    let bytes: Int64
    let modified: Date
    let identity: FileIdentity
    /// For project artifacts: a sibling file (e.g. package.json) that must still exist at cleanup time.
    let requiredMarker: URL?
    /// False for items Orbit only reports (e.g. Docker's VM disk). They can't be selected or removed.
    var selectable = true
}

nonisolated struct DevProgress: Sendable {
    var itemsFound = 0
    var current = ""
}

nonisolated struct DevScanResult: Sendable {
    let home: URL
    var finishedAt: Date
    var status: ScanStatus
    var items: [DevItem]
    var skippedCount: Int
}

nonisolated struct DevItemResult: Identifiable, Sendable {
    var id: String { item.id }
    let item: DevItem
    let outcome: CleanupOutcome
    /// Where the item sits in the Trash after a successful move, when macOS reports it.
    var trashedURL: URL?
}

nonisolated struct DevCleanupReport: Sendable {
    let results: [DevItemResult]
    var completed: [DevItemResult] { results.filter { $0.outcome == .completed } }
    var notCompleted: [DevItemResult] { results.filter { $0.outcome != .completed } }
    /// Estimate: sizes of folders moved to the Trash. Space is only freed once the Trash is emptied.
    var estimatedMovedBytes: Int64 { completed.reduce(0) { $0 + $1.item.bytes } }
}

/// A well-known cache location under the user's home folder, with its eligibility rationale.
nonisolated struct KnownLocation: Sendable {
    let relativePath: String
    let title: String
    let tool: String
    let group: DevGroup
    let risk: DevRisk
    let reason: String
    var selectable = true
}

/// A project-level artifact folder that qualifies only when a marker file proves what it belongs to.
nonisolated struct ArtifactRule: Sendable {
    let folderName: String
    /// Any one of these must exist next to the folder (or inside it, when `markerInside`).
    let markers: [String]
    let markerInside: Bool
    let tool: String
    let reason: String
    /// Only searched in Deep cleanup. A marker beginning with `*.` matches any file with that extension.
    var deepOnly = false
}

nonisolated enum DevCatalog {
    private static let quit = " Quit the app before cleaning."

    static let locations: [KnownLocation] = [
        // Build tools & package managers
        .init(relativePath: ".gradle/caches", title: "Gradle caches", tool: "Gradle", group: .buildTools, risk: .regenerable,
              reason: "Downloaded dependencies and build caches. Gradle re-downloads them on the next build, which needs network."),
        .init(relativePath: ".gradle/daemon", title: "Gradle daemon logs", tool: "Gradle", group: .buildTools, risk: .regenerable,
              reason: "Daemon logs and registry. Recreated when Gradle starts."),
        .init(relativePath: ".gradle/wrapper/dists", title: "Gradle distributions", tool: "Gradle", group: .buildTools, risk: .regenerable,
              reason: "Gradle versions fetched by project wrappers. Re-downloaded the next time a project uses one."),
        .init(relativePath: ".m2/repository", title: "Maven local repository", tool: "Maven", group: .buildTools, risk: .caution,
              reason: "Downloaded artifacts are re-fetched, but artifacts you installed locally with `mvn install` can't be, and offline builds will break."),
        .init(relativePath: ".npm/_cacache", title: "npm cache", tool: "npm", group: .node, risk: .regenerable,
              reason: "Content-addressed download cache. npm refills it as needed."),
        .init(relativePath: "Library/Caches/Yarn", title: "Yarn cache", tool: "Yarn", group: .node, risk: .regenerable,
              reason: "Package download cache. Yarn refills it as needed."),
        .init(relativePath: "Library/pnpm/store", title: "pnpm store", tool: "pnpm", group: .node, risk: .regenerable,
              reason: "Shared package store. Installed projects keep working; the next install re-downloads what's missing."),
        .init(relativePath: "Library/Caches/pip", title: "pip cache", tool: "Python", group: .buildTools, risk: .regenerable,
              reason: "Downloaded wheels and HTTP cache. pip refills it as needed."),
        .init(relativePath: ".cargo/registry/cache", title: "Cargo registry cache", tool: "Rust", group: .buildTools, risk: .regenerable,
              reason: "Downloaded crate archives. Cargo re-downloads them when a build needs them."),
        .init(relativePath: "Library/Caches/go-build", title: "Go build cache", tool: "Go", group: .buildTools, risk: .regenerable,
              reason: "Compiled package cache. Rebuilt on the next build."),
        .init(relativePath: "Library/Caches/CocoaPods", title: "CocoaPods cache", tool: "CocoaPods", group: .buildTools, risk: .regenerable,
              reason: "Downloaded pod sources. Re-fetched on the next `pod install`."),
        .init(relativePath: "Library/Caches/org.swift.swiftpm", title: "SwiftPM cache", tool: "Swift Package Manager", group: .buildTools, risk: .regenerable,
              reason: "Cached package repositories. Re-fetched on the next resolve."),
        .init(relativePath: "Library/Caches/Homebrew", title: "Homebrew downloads", tool: "Homebrew", group: .brew, risk: .regenerable,
              reason: "Downloaded bottles and sources. Re-downloaded on the next install or upgrade."),

        // Xcode
        .init(relativePath: "Library/Developer/Xcode/DerivedData", title: "Xcode DerivedData", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Build products and indexes. Xcode rebuilds them, so the next build is slower." + quit),
        .init(relativePath: "Library/Developer/Xcode/iOS DeviceSupport", title: "iOS DeviceSupport", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Device debug symbols. Copied again from the device the next time you connect it."),
        .init(relativePath: "Library/Developer/CoreSimulator/Caches", title: "Simulator caches", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Simulator runtime caches. Rebuilt when simulators launch." + quit),

        // More package managers & toolchains
        .init(relativePath: ".bun/install/cache", title: "Bun cache", tool: "Bun", group: .node, risk: .regenerable,
              reason: "Package download cache. Bun refills it as needed."),
        .init(relativePath: "Library/Caches/deno", title: "Deno cache", tool: "Deno", group: .node, risk: .regenerable,
              reason: "Downloaded modules and compiled output. Re-fetched on demand."),
        .init(relativePath: ".yarn/berry/cache", title: "Yarn Berry cache", tool: "Yarn", group: .node, risk: .regenerable,
              reason: "Global package archive cache. Re-downloaded on the next install."),
        .init(relativePath: "Library/Caches/pypoetry", title: "Poetry cache", tool: "Python", group: .buildTools, risk: .regenerable,
              reason: "Downloaded packages and virtualenvs created by Poetry. Recreated on the next install."),
        .init(relativePath: ".conda/pkgs", title: "Conda package cache", tool: "Conda", group: .buildTools, risk: .regenerable,
              reason: "Downloaded packages. Re-fetched when an environment needs them."),
        .init(relativePath: ".composer/cache", title: "Composer cache", tool: "PHP", group: .buildTools, risk: .regenerable,
              reason: "Downloaded package archives. Refilled on demand."),
        .init(relativePath: ".nuget/packages", title: "NuGet packages", tool: ".NET", group: .buildTools, risk: .regenerable,
              reason: "Restored packages. Re-created by `dotnet restore` (needs network)."),
        .init(relativePath: ".pub-cache", title: "Dart / Flutter pub cache", tool: "Flutter", group: .buildTools, risk: .caution,
              reason: "Re-downloaded by `pub get`, but globally activated tools must be activated again."),
        .init(relativePath: ".ivy2/cache", title: "Ivy cache", tool: "sbt", group: .buildTools, risk: .regenerable,
              reason: "Downloaded dependencies. Re-fetched on the next build."),
        .init(relativePath: "Library/Caches/Coursier", title: "Coursier cache", tool: "Scala", group: .buildTools, risk: .regenerable,
              reason: "Downloaded dependencies. Re-fetched on demand."),
        .init(relativePath: ".terraform.d/plugin-cache", title: "Terraform plugin cache", tool: "Terraform", group: .buildTools, risk: .regenerable,
              reason: "Provider binaries. Re-downloaded by `terraform init`."),
        .init(relativePath: ".android/cache", title: "Android SDK cache", tool: "Android", group: .buildTools, risk: .regenerable,
              reason: "SDK manager download cache. Refilled on demand."),
        .init(relativePath: "Library/Caches/JetBrains", title: "JetBrains IDE caches", tool: "JetBrains", group: .agents, risk: .regenerable,
              reason: "IDE indexes and caches. Rebuilt on next launch, which re-indexes projects." + quit),
        .init(relativePath: "Library/Logs/JetBrains", title: "JetBrains logs", tool: "JetBrains", group: .agents, risk: .regenerable,
              reason: "IDE logs only."),
        .init(relativePath: "Library/Caches/Zed", title: "Zed cache", tool: "Zed", group: .agents, risk: .regenerable,
              reason: "Editor cache. Recreated on use." + quit),
        .init(relativePath: ".cache/huggingface", title: "Hugging Face model cache", tool: "ML tooling", group: .buildTools, risk: .caution,
              reason: "Downloaded models and datasets. Re-downloadable, but can be very large and slow to fetch again."),
        .init(relativePath: ".ollama/models", title: "Ollama models", tool: "Ollama", group: .agents, risk: .caution,
              reason: "Locally pulled LLMs. Each must be pulled again, which can be many GB."),

        // Xcode: data that can't simply be rebuilt
        .init(relativePath: "Library/Developer/Xcode/Archives", title: "Xcode Archives", tool: "Xcode", group: .xcode, risk: .caution,
              reason: "App archives and dSYMs used for symbolication and re-submission. Can't be regenerated from source reliably."),
        .init(relativePath: "Library/Developer/CoreSimulator/Devices", title: "Simulator devices & app data", tool: "Xcode", group: .xcode, risk: .caution,
              reason: "Installed simulator apps and their data. Removing resets simulators and can leave Xcode confused; quit Xcode and Simulator first."),

        // Toolchain & test-runner caches
        .init(relativePath: ".cargo/git", title: "Cargo git checkouts", tool: "Rust", group: .buildTools, risk: .regenerable,
              reason: "Cloned git dependencies. Re-cloned when a build needs them."),
        .init(relativePath: ".cargo/registry/src", title: "Cargo extracted sources", tool: "Rust", group: .buildTools, risk: .regenerable,
              reason: "Unpacked crate sources. Re-extracted from the registry cache."),
        .init(relativePath: ".rustup/toolchains", title: "Rust toolchains", tool: "Rust", group: .buildTools, risk: .caution,
              reason: "Installed compilers. Reinstallable with rustup, but projects fail to build until you do."),
        .init(relativePath: ".sdkman/archives", title: "SDKMAN downloads", tool: "SDKMAN", group: .buildTools, risk: .regenerable,
              reason: "Downloaded SDK archives. Installed SDKs are kept elsewhere."),
        .init(relativePath: ".nvm/.cache", title: "nvm download cache", tool: "nvm", group: .node, risk: .regenerable,
              reason: "Downloaded Node tarballs. Re-fetched on install."),
        .init(relativePath: "Library/Caches/node-gyp", title: "node-gyp headers", tool: "Node.js", group: .node, risk: .regenerable,
              reason: "Node headers for native builds. Re-downloaded when needed."),
        .init(relativePath: "Library/Caches/ms-playwright", title: "Playwright browsers", tool: "Playwright", group: .node, risk: .regenerable,
              reason: "Downloaded test browsers. Re-installed with `npx playwright install`."),
        .init(relativePath: ".cache/puppeteer", title: "Puppeteer browsers", tool: "Puppeteer", group: .node, risk: .regenerable,
              reason: "Downloaded Chrome builds. Re-downloaded on demand."),
        .init(relativePath: "Library/Caches/Cypress", title: "Cypress binaries", tool: "Cypress", group: .node, risk: .regenerable,
              reason: "Downloaded Cypress app. Re-downloaded by `cypress install`."),
        .init(relativePath: "Library/Caches/electron", title: "Electron downloads", tool: "Electron", group: .node, risk: .regenerable,
              reason: "Downloaded Electron builds. Re-downloaded when packaging."),
        .init(relativePath: "Library/Caches/uv", title: "uv cache", tool: "Python", group: .buildTools, risk: .regenerable,
              reason: "Package cache. Refilled on demand."),
        .init(relativePath: ".cache/uv", title: "uv cache (XDG)", tool: "Python", group: .buildTools, risk: .regenerable,
              reason: "Package cache. Refilled on demand."),
        .init(relativePath: ".cache/pre-commit", title: "pre-commit environments", tool: "pre-commit", group: .buildTools, risk: .regenerable,
              reason: "Hook environments. Rebuilt on the next commit."),
        .init(relativePath: ".local/share/virtualenvs", title: "Pipenv virtualenvs", tool: "Python", group: .buildTools, risk: .caution,
              reason: "Environments for your projects. Recreating them needs a reinstall and may change pinned versions."),
        .init(relativePath: ".kube/cache", title: "kubectl cache", tool: "Kubernetes", group: .buildTools, risk: .regenerable,
              reason: "API discovery cache. Recreated on use."),
        .init(relativePath: ".minikube/cache", title: "minikube cache", tool: "Kubernetes", group: .buildTools, risk: .regenerable,
              reason: "Downloaded images and binaries. Re-downloaded on `minikube start`."),
        .init(relativePath: ".aws/cli/cache", title: "AWS CLI cache", tool: "AWS", group: .buildTools, risk: .regenerable,
              reason: "Cached credentials responses. You may need to sign in again."),

        // More Xcode
        .init(relativePath: "Library/Developer/Xcode/macOS DeviceSupport", title: "macOS DeviceSupport", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Debug symbols. Recreated when needed."),
        .init(relativePath: "Library/Developer/Xcode/watchOS DeviceSupport", title: "watchOS DeviceSupport", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Device debug symbols. Copied again when you connect the device."),
        .init(relativePath: "Library/Developer/Xcode/tvOS DeviceSupport", title: "tvOS DeviceSupport", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Device debug symbols. Copied again when you connect the device."),
        .init(relativePath: "Library/Developer/Shared/Documentation/DocSets", title: "Xcode documentation sets", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Downloaded documentation. Re-downloadable from Xcode."),
        .init(relativePath: "Library/Caches/com.apple.dt.Xcode", title: "Xcode caches", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Xcode cache. Rebuilt on use." + quit),

        // System junk (user-level)
        .init(relativePath: "Library/Logs/DiagnosticReports", title: "Crash & diagnostic reports", tool: "macOS", group: .systemJunk, risk: .regenerable,
              reason: "Crash reports. Useful only for troubleshooting."),
        .init(relativePath: "Library/Application Support/CrashReporter", title: "Crash reporter data", tool: "macOS", group: .systemJunk, risk: .regenerable,
              reason: "Crash reporter records. Useful only for troubleshooting."),
        .init(relativePath: "Library/Caches/com.apple.QuickLook.thumbnailcache", title: "Quick Look thumbnails", tool: "macOS", group: .systemJunk, risk: .regenerable,
              reason: "Preview thumbnails. Rebuilt as you browse files."),
        .init(relativePath: "Library/Saved Application State", title: "Saved window state", tool: "macOS", group: .systemJunk, risk: .regenerable,
              reason: "Window restore data. Apps reopen without their previous windows."),
        .init(relativePath: "Library/Application Support/MobileSync/Backup", title: "iOS device backups", tool: "Finder", group: .systemJunk, risk: .caution,
              reason: "Backups of iPhones and iPads. May be the only backup of a device."),

        // Mail
        .init(relativePath: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads", title: "Mail attachment copies", tool: "Mail", group: .mailFiles, risk: .caution,
              reason: "Copies of attachments you opened. Originals stay in your mailbox, but edits you made to these copies would be lost."),
        .init(relativePath: "Library/Mail Downloads", title: "Mail attachment copies (legacy)", tool: "Mail", group: .mailFiles, risk: .caution,
              reason: "Copies of attachments you opened. Originals stay in your mailbox, but edits you made to these copies would be lost."),

        // Brew & Docker
        .init(relativePath: "Library/Logs/Homebrew", title: "Homebrew logs", tool: "Homebrew", group: .brew, risk: .regenerable,
              reason: "Install and upgrade logs. Recreated on use."),
        .init(relativePath: ".cache/Homebrew", title: "Homebrew cache (XDG)", tool: "Homebrew", group: .brew, risk: .regenerable,
              reason: "Downloaded bottles and sources. Re-downloaded on demand."),
        .init(relativePath: "Library/Caches/com.docker.docker", title: "Docker Desktop cache", tool: "Docker", group: .docker, risk: .regenerable,
              reason: "App cache. Recreated on launch. Quit Docker Desktop first."),
        .init(relativePath: "Library/Containers/com.docker.docker/Data/log", title: "Docker Desktop logs", tool: "Docker", group: .docker, risk: .regenerable,
              reason: "Diagnostic logs. Recreated on launch. Quit Docker Desktop first."),
        .init(relativePath: ".docker/buildx", title: "Docker buildx state", tool: "Docker", group: .docker, risk: .caution,
              reason: "Builder configuration and activity. Removing it resets custom builders."),
        .init(relativePath: "Library/Containers/com.docker.docker/Data/vms", title: "Docker Desktop VM disk", tool: "Docker", group: .docker, risk: .caution,
              reason: "Images, containers and volumes live in this disk image. Deleting it would destroy them and break Docker, so Orbit only reports it. To reclaim space use Docker Desktop's Troubleshoot ▸ Clean / Purge data, or `docker system prune`.",
              selectable: false),
        .init(relativePath: ".colima", title: "Colima VM data", tool: "Docker", group: .docker, risk: .caution,
              reason: "Colima's virtual machine and its images and containers. Orbit only reports it; use `docker system prune` or `colima delete`.",
              selectable: false),
        .init(relativePath: "Library/Group Containers/HUAQ24HBR6.dev.orbstack/data", title: "OrbStack data", tool: "Docker", group: .docker, risk: .caution,
              reason: "OrbStack's machines, images and containers. Orbit only reports it; clean it from OrbStack.",
              selectable: false),

        // More cleanup rules: JVM, Python, Ruby, Go, Rust, Swift, mobile
        .init(relativePath: ".gradle/jdks", title: "Gradle-provisioned JDKs", tool: "Gradle", group: .buildTools, risk: .regenerable,
              reason: "JDKs Gradle toolchains downloaded. Re-downloaded when a build needs one."),
        .init(relativePath: ".gradle/native", title: "Gradle native libraries", tool: "Gradle", group: .buildTools, risk: .regenerable,
              reason: "Extracted native helpers. Recreated on the next run."),
        .init(relativePath: ".m2/wrapper", title: "Maven wrapper distributions", tool: "Maven", group: .buildTools, risk: .regenerable,
              reason: "Maven versions fetched by project wrappers. Re-downloaded when a project uses one."),
        .init(relativePath: ".konan", title: "Kotlin/Native cache", tool: "Kotlin", group: .buildTools, risk: .regenerable,
              reason: "Downloaded Kotlin/Native toolchains and dependencies. Re-downloaded on demand."),
        .init(relativePath: ".sbt/boot", title: "sbt boot cache", tool: "sbt", group: .buildTools, risk: .regenerable,
              reason: "sbt launcher downloads. Re-fetched on the next run."),
        .init(relativePath: ".cache/pip", title: "pip cache (XDG)", tool: "Python", group: .buildTools, risk: .regenerable,
              reason: "Downloaded wheels. pip refills it as needed."),
        .init(relativePath: "Library/Caches/pipenv", title: "Pipenv cache", tool: "Python", group: .buildTools, risk: .regenerable,
              reason: "Pipenv download cache. Refilled as needed."),
        .init(relativePath: ".pyenv/cache", title: "pyenv download cache", tool: "Python", group: .buildTools, risk: .regenerable,
              reason: "Downloaded Python source archives. Re-downloaded on install."),
        .init(relativePath: ".cache/torch", title: "PyTorch model cache", tool: "ML tooling", group: .buildTools, risk: .caution,
              reason: "Downloaded pretrained weights. Re-downloadable but can be large and slow to fetch again."),
        .init(relativePath: ".keras/models", title: "Keras model cache", tool: "ML tooling", group: .buildTools, risk: .caution,
              reason: "Downloaded pretrained models. Re-downloadable but can be large."),
        .init(relativePath: ".jupyter/runtime", title: "Jupyter runtime files", tool: "Jupyter", group: .buildTools, risk: .regenerable,
              reason: "Kernel connection files. Recreated when kernels start."),
        .init(relativePath: ".bundle/cache", title: "Bundler cache", tool: "Ruby", group: .buildTools, risk: .regenerable,
              reason: "Downloaded gems. Re-fetched by `bundle install`."),
        .init(relativePath: ".cocoapods/repos", title: "CocoaPods spec repos", tool: "CocoaPods", group: .buildTools, risk: .regenerable,
              reason: "Local copy of the pod specs. Re-cloned on the next `pod install` (slow, large download)."),
        .init(relativePath: "go/pkg/mod/cache", title: "Go module cache", tool: "Go", group: .buildTools, risk: .regenerable,
              reason: "Downloaded modules. Re-fetched by `go mod download`."),
        .init(relativePath: ".cargo/registry/index", title: "Cargo registry index", tool: "Rust", group: .buildTools, risk: .regenerable,
              reason: "Crate index. Re-fetched on the next build."),
        .init(relativePath: "Library/Caches/typescript", title: "TypeScript cache", tool: "TypeScript", group: .node, risk: .regenerable,
              reason: "Type acquisition cache. Recreated by the editor."),
        .init(relativePath: ".npm/_logs", title: "npm logs", tool: "npm", group: .node, risk: .regenerable,
              reason: "Debug logs from past npm runs."),
        .init(relativePath: ".npm/_npx", title: "npx cache", tool: "npm", group: .node, risk: .regenerable,
              reason: "Temporary packages fetched by `npx`. Re-downloaded when used again."),
        .init(relativePath: "Library/Caches/pnpm", title: "pnpm metadata cache", tool: "pnpm", group: .node, risk: .regenerable,
              reason: "Registry metadata. Refilled as needed."),
        .init(relativePath: ".pnpm-store", title: "pnpm store (legacy location)", tool: "pnpm", group: .node, risk: .regenerable,
              reason: "Shared package store. Installed projects keep working; the next install re-downloads what's missing."),
        .init(relativePath: "Library/Developer/Xcode/UserData/Previews", title: "SwiftUI preview data", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Preview build caches and simulators. Rebuilt when previews run." + quit),
        .init(relativePath: "Library/Developer/Xcode/DocumentationCache", title: "Xcode documentation cache", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Cached documentation indexes. Rebuilt on demand."),
        .init(relativePath: "Library/Developer/Xcode/UserData/IB Support", title: "Interface Builder support", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Interface Builder caches. Rebuilt on demand."),
        .init(relativePath: "Library/Logs/CoreSimulator", title: "Simulator logs", tool: "Xcode", group: .xcode, risk: .regenerable,
              reason: "Simulator diagnostic logs."),
        .init(relativePath: ".android/avd", title: "Android virtual devices", tool: "Android", group: .buildTools, risk: .caution,
              reason: "Emulator images and their data. Recreating them takes time and loses emulator app data."),
        .init(relativePath: "Library/Android/sdk/system-images", title: "Android system images", tool: "Android", group: .buildTools, risk: .caution,
              reason: "Emulator system images. Re-downloadable in the SDK Manager, but large."),
        .init(relativePath: ".claude/debug", title: "Claude Code debug logs", tool: "Claude Code", group: .agents, risk: .regenerable,
              reason: "Debug logs from past sessions."),
        .init(relativePath: ".claude/statsig", title: "Claude Code feature cache", tool: "Claude Code", group: .agents, risk: .regenerable,
              reason: "Cached feature-flag data. Recreated on use."),
        .init(relativePath: ".claude/todos", title: "Claude Code task lists", tool: "Claude Code", group: .agents, risk: .caution,
              reason: "Per-session task lists. Removing them loses the to-do state of past sessions."),
        .init(relativePath: ".ollama/logs", title: "Ollama logs", tool: "Ollama", group: .agents, risk: .regenerable,
              reason: "Server logs only."),

        // AI coding agents & editors (paths are best effort; only folders that exist are listed)
        .init(relativePath: "Library/Caches/claude-cli-nodejs", title: "Claude Code cache", tool: "Claude Code", group: .agents, risk: .regenerable,
              reason: "Cached data. Recreated on use."),
        .init(relativePath: "Library/Logs/Claude", title: "Claude logs", tool: "Claude", group: .agents, risk: .regenerable,
              reason: "Diagnostic logs only."),
        .init(relativePath: ".claude/shell-snapshots", title: "Claude Code shell snapshots", tool: "Claude Code", group: .agents, risk: .regenerable,
              reason: "Temporary shell environment snapshots. Recreated per session."),
        .init(relativePath: ".claude/projects", title: "Claude Code session history", tool: "Claude Code", group: .agents, risk: .caution,
              reason: "Conversation transcripts per project. Removing them deletes your history and the ability to resume past sessions."),
        .init(relativePath: "Library/Caches/com.todesktop.230313mzl4w4u92", title: "Cursor app cache", tool: "Cursor", group: .agents, risk: .regenerable,
              reason: "Application cache. Recreated on use." + quit),
    ] + [("Cursor", "Cursor"), ("Antigravity", "Antigravity"), ("Code", "VS Code"), ("Windsurf", "Windsurf"), ("Claude", "Claude")]
        .flatMap { folderName, title in
            ["Cache", "CachedData", "Code Cache", "GPUCache", "logs", "CachedExtensionVSIXs", "Crashpad", "DawnCache", "Service Worker/CacheStorage"].map { folder in
                KnownLocation(relativePath: "Library/Application Support/\(folderName)/\(folder)", title: "\(title) \(folder)", tool: title,
                              group: .agents, risk: .regenerable,
                              reason: "Editor/app \(folder == "logs" ? "logs" : "cache") (Electron layout). Recreated on launch." + quit)
            }
        }
    + ["Cursor", "Antigravity", "Code", "Windsurf"].map { app in
        KnownLocation(relativePath: "Library/Application Support/\(app)/User/workspaceStorage", title: "\(app == "Code" ? "VS Code" : app) workspace storage",
                      tool: app == "Code" ? "VS Code" : app, group: .agents, risk: .caution,
                      reason: "Per-workspace state, including editor and chat history for each project. Removing it resets that state." + quit)
    }

    static let artifactRules: [ArtifactRule] = [
        .init(folderName: "node_modules", markers: ["package.json"], markerInside: false, tool: "Node.js",
              reason: "Installed dependencies. Restore with your package manager's install command."),
        .init(folderName: ".next", markers: ["package.json"], markerInside: false, tool: "Next.js",
              reason: "Build output and cache. Recreated by the next build or dev run."),
        .init(folderName: "target", markers: ["Cargo.toml", "pom.xml"], markerInside: false, tool: "Rust / Maven",
              reason: "Compiler output. Recreated by the next build."),
        .init(folderName: "build", markers: ["build.gradle", "build.gradle.kts", "pubspec.yaml", "CMakeLists.txt"], markerInside: false,
              tool: "Gradle / Flutter", reason: "Build output. Recreated by the next build."),
        .init(folderName: ".dart_tool", markers: ["pubspec.yaml"], markerInside: false, tool: "Dart",
              reason: "Tooling cache. Recreated by `pub get`."),
        .init(folderName: ".build", markers: ["Package.swift"], markerInside: false, tool: "SwiftPM",
              reason: "Swift package build output. Recreated by the next build."),
        .init(folderName: ".turbo", markers: ["package.json"], markerInside: false, tool: "Turborepo",
              reason: "Task cache. Recreated by the next run."),
        .init(folderName: ".nuxt", markers: ["package.json"], markerInside: false, tool: "Nuxt",
              reason: "Build output. Recreated by the next build or dev run."),
        .init(folderName: ".angular", markers: ["angular.json"], markerInside: false, tool: "Angular",
              reason: "Build cache. Recreated by the next build."),
        .init(folderName: ".terraform", markers: ["main.tf", "versions.tf"], markerInside: false, tool: "Terraform",
              reason: "Downloaded providers and modules. Restore with `terraform init`."),
        .init(folderName: ".gradle", markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
              markerInside: false, tool: "Gradle", reason: "Project-level Gradle cache. Recreated by the next build."),
        .init(folderName: "__pycache__", markers: ["*.py"], markerInside: false, tool: "Python",
              reason: "Compiled bytecode. Regenerated automatically.", deepOnly: true),
        .init(folderName: ".pytest_cache", markers: ["*.py"], markerInside: false, tool: "pytest",
              reason: "Test run cache. Recreated by the next run.", deepOnly: true),
        .init(folderName: ".mypy_cache", markers: ["*.py"], markerInside: false, tool: "mypy",
              reason: "Type-check cache. Recreated by the next run.", deepOnly: true),
        .init(folderName: ".ruff_cache", markers: ["*.py"], markerInside: false, tool: "Ruff",
              reason: "Lint cache. Recreated by the next run.", deepOnly: true),
        .init(folderName: ".tox", markers: ["tox.ini"], markerInside: false, tool: "tox",
              reason: "Test environments. Recreated by `tox`.", deepOnly: true),
        .init(folderName: "obj", markers: ["*.csproj", "*.fsproj"], markerInside: false, tool: ".NET",
              reason: "Intermediate build output. Recreated by the next build.", deepOnly: true),
        .init(folderName: "bin", markers: ["*.csproj", "*.fsproj"], markerInside: false, tool: ".NET",
              reason: "Build output. Recreated by the next build.", deepOnly: true),
        .init(folderName: ".parcel-cache", markers: ["package.json"], markerInside: false, tool: "Parcel",
              reason: "Build cache. Recreated by the next build."),
        .init(folderName: ".svelte-kit", markers: ["package.json"], markerInside: false, tool: "SvelteKit",
              reason: "Generated output. Recreated by the next dev run or build."),
        .init(folderName: ".expo", markers: ["package.json"], markerInside: false, tool: "Expo",
              reason: "Local Expo state. Recreated on the next start."),
        .init(folderName: ".docusaurus", markers: ["package.json"], markerInside: false, tool: "Docusaurus",
              reason: "Generated output. Recreated by the next build."),
        .init(folderName: "DerivedData", markers: ["*.xcodeproj", "*.xcworkspace", "Package.swift"], markerInside: false, tool: "Xcode",
              reason: "Project-local build products. Rebuilt by Xcode."),
        .init(folderName: "cmake-build-debug", markers: ["CMakeLists.txt"], markerInside: false, tool: "CMake",
              reason: "CLion/CMake build output. Recreated by the next build."),
        .init(folderName: "cmake-build-release", markers: ["CMakeLists.txt"], markerInside: false, tool: "CMake",
              reason: "CLion/CMake build output. Recreated by the next build."),
        .init(folderName: ".serverless", markers: ["serverless.yml", "serverless.yaml"], markerInside: false, tool: "Serverless",
              reason: "Packaged deployment artifacts. Recreated on deploy."),
        .init(folderName: ".aws-sam", markers: ["template.yaml", "template.yml"], markerInside: false, tool: "AWS SAM",
              reason: "Build artifacts. Recreated by `sam build`."),
        .init(folderName: "elm-stuff", markers: ["elm.json"], markerInside: false, tool: "Elm",
              reason: "Compiler cache. Recreated by the next build."),
        .init(folderName: "_build", markers: ["mix.exs"], markerInside: false, tool: "Elixir",
              reason: "Compiled output. Recreated by `mix compile`."),
        .init(folderName: "deps", markers: ["mix.exs"], markerInside: false, tool: "Elixir",
              reason: "Fetched dependencies. Restore with `mix deps.get`."),
        .init(folderName: ".stack-work", markers: ["stack.yaml"], markerInside: false, tool: "Haskell",
              reason: "Stack build output. Recreated by the next build."),
        .init(folderName: "dist-newstyle", markers: ["*.cabal", "cabal.project"], markerInside: false, tool: "Haskell",
              reason: "Cabal build output. Recreated by the next build."),
        .init(folderName: ".zig-cache", markers: ["build.zig"], markerInside: false, tool: "Zig",
              reason: "Compiler cache. Recreated by the next build."),
        .init(folderName: "zig-cache", markers: ["build.zig"], markerInside: false, tool: "Zig",
              reason: "Compiler cache. Recreated by the next build."),
        .init(folderName: ".eggs", markers: ["setup.py"], markerInside: false, tool: "Python",
              reason: "Build-time eggs. Recreated by `setup.py`."),
        .init(folderName: "coverage", markers: ["package.json"], markerInside: false, tool: "Test coverage",
              reason: "Generated coverage reports. Recreated by the next test run.", deepOnly: true),
        .init(folderName: "htmlcov", markers: ["*.py"], markerInside: false, tool: "Test coverage",
              reason: "Generated coverage report. Recreated by the next test run.", deepOnly: true),
        .init(folderName: ".ipynb_checkpoints", markers: ["*.ipynb"], markerInside: false, tool: "Jupyter",
              reason: "Notebook autosave checkpoints. Your notebooks are not in this folder.", deepOnly: true),
        .init(folderName: "Pods", markers: ["Podfile"], markerInside: false, tool: "CocoaPods",
              reason: "Installed pods. Restore with `pod install`."),
        .init(folderName: ".venv", markers: ["pyvenv.cfg"], markerInside: true, tool: "Python",
              reason: "Virtual environment. Recreate it and reinstall requirements."),
        .init(folderName: "venv", markers: ["pyvenv.cfg"], markerInside: true, tool: "Python",
              reason: "Virtual environment. Recreate it and reinstall requirements."),
    ]
}
