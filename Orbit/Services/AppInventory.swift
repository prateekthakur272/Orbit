//
//  AppInventory.swift
//  Orbit
//

import Foundation

nonisolated struct AppInfo: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let isAppStore: Bool
    let bytes: Int64
    let modified: Date
    let identity: FileIdentity
}

nonisolated struct RelatedFile: Identifiable, Sendable {
    var id: String { item.id }
    let item: DevItem
    /// Matched by exact bundle identifier (strong) rather than by app name (weak).
    let strongMatch: Bool
}

/// Read-only inventory of installed apps and the support files that belong to them.
nonisolated enum AppInventory {
    static var applicationRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"), DevCleanupModelHome.home.appendingPathComponent("Applications")]
    }

    static func installedApps(roots: [URL]) async -> [AppInfo] {
        await Task.detached(priority: .userInitiated) { scanApps(roots: roots) }.value
    }

    static func scanApps(roots: [URL]) -> [AppInfo] {
        var apps: [AppInfo] = []
        let fm = FileManager.default
        for root in roots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            var candidates = children
            // One level of grouping folders such as /Applications/Utilities.
            for child in children where child.pathExtension != "app" && (FileIdentity.current(at: child)?.isDirectory ?? false) {
                candidates += (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            }
            for url in candidates where url.pathExtension == "app" {
                if Task.isCancelled { return apps }
                guard let identity = FileIdentity.current(at: url), identity.isDirectory else { continue }
                let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
                let bundleID = info?["CFBundleIdentifier"] as? String
                if bundleID?.hasPrefix("com.apple.") == true { continue }   // Apple apps are never uninstall candidates
                let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String)
                let receipt = fm.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
                apps.append(AppInfo(url: url, name: name, bundleID: bundleID, version: version, isAppStore: receipt,
                                    bytes: DevScanner.directorySize(url) ?? 0, modified: DevScanner.modified(url), identity: identity))
            }
        }
        return apps.sorted { $0.bytes > $1.bytes }
    }

    /// Support files for `app` that exist under `home`. Exact bundle-ID matches are strong; name matches are weak.
    static func relatedFiles(for app: AppInfo, home: URL) -> [RelatedFile] {
        var specs: [(String, String, Bool, String)] = []   // (relative path, title, strong, reason)
        if let id = app.bundleID {
            let strong = "Matches this app's bundle identifier."
            specs += [
                ("Library/Application Support/\(id)", "Application Support", true, strong + " Contains the app's data."),
                ("Library/Caches/\(id)", "Caches", true, strong + " Rebuildable cache."),
                ("Library/Preferences/\(id).plist", "Preferences", true, strong + " The app's settings."),
                ("Library/Containers/\(id)", "Sandbox container", true, strong + " The app's sandboxed data."),
                ("Library/Saved Application State/\(id).savedState", "Saved window state", true, strong),
                ("Library/HTTPStorages/\(id)", "HTTP storage", true, strong),
                ("Library/WebKit/\(id)", "WebKit data", true, strong),
                ("Library/Application Scripts/\(id)", "Application scripts", true, strong),
                ("Library/Logs/\(id)", "Logs", true, strong),
                ("Library/LaunchAgents/\(id).plist", "Launch agent", true, strong + " May start a helper at login."),
            ]
        }
        let weak = "Matches the app's name only, so it might belong to something else."
        specs += [
            ("Library/Application Support/\(app.name)", "Application Support (by name)", false, weak),
            ("Library/Logs/\(app.name)", "Logs (by name)", false, weak),
        ]
        var seen = Set<String>()
        return specs.compactMap { rel, title, strong, reason in
            let url = home.appendingPathComponent(rel)
            guard seen.insert(url.path).inserted, let identity = FileIdentity.current(at: url),
                  identity.isDirectory || identity.isRegularFile else { return nil }
            let size = identity.isDirectory ? (DevScanner.directorySize(url) ?? 0) : identity.size
            return RelatedFile(item: DevItem(url: url, title: title, tool: app.name, group: .leftovers, risk: strong ? .regenerable : .caution,
                                             reason: reason, bytes: size, modified: DevScanner.modified(url), identity: identity,
                                             requiredMarker: nil), strongMatch: strong)
        }
    }

    static func item(for app: AppInfo) -> DevItem {
        DevItem(url: app.url, title: app.name + ".app", tool: "Application", group: .leftovers, risk: .caution,
                reason: "The application itself.", bytes: app.bytes, modified: app.modified, identity: app.identity, requiredMarker: nil)
    }
}

enum DevCleanupModelHome {
    static var home: URL {
        URL(fileURLWithPath: getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory())
    }
}
