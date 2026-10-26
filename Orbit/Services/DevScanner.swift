//
//  DevScanner.swift
//  Orbit
//

import CoreServices
import Foundation

/// Read-only scanner for developer caches, system junk and project build artifacts.
nonisolated struct DevScanner: Sendable {
    func scan(home: URL, groups: Set<DevGroup> = Set(DevGroup.allCases), deep: Bool = false,
              progress: @escaping @Sendable (DevProgress) -> Void) async -> DevScanResult {
        let task = Task.detached(priority: .userInitiated) { run(home: home, groups: groups, deep: deep, progress: progress) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    /// Items smaller than this are left out of per-app listings to avoid noise.
    static let childMinimumBytes: Int64 = 5_000_000
    static let staleInstallerDays = 30

    private func run(home: URL, groups: Set<DevGroup>, deep: Bool, progress: @Sendable (DevProgress) -> Void) -> DevScanResult {
        var result = DevScanResult(home: home, finishedAt: Date(), status: .completed, items: [], skippedCount: 0)
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: home.path)
        } catch {
            result.status = .failed("Orbit can't read your home folder (\(error.localizedDescription)). Grant access and try again.")
            return result
        }

        var items: [DevItem] = []
        var skipped = 0
        var cancelled = false

        // 1. Known locations.
        for location in DevCatalog.locations where groups.contains(location.group) {
            if Task.isCancelled { cancelled = true; break }
            let url = home.appendingPathComponent(location.relativePath)
            guard let identity = FileIdentity.current(at: url), identity.isDirectory else { continue }
            progress(DevProgress(itemsFound: items.count, current: location.title))
            guard let size = Self.directorySize(url) else { cancelled = true; break }
            if size == 0 { continue }
            items.append(DevItem(
                url: url, title: location.title, tool: location.tool, group: location.group, risk: location.risk,
                reason: location.reason, bytes: size, modified: Self.modified(url), identity: identity, requiredMarker: nil,
                selectable: location.selectable
            ))
        }

        let covered = Set(DevCatalog.locations.map { home.appendingPathComponent($0.relativePath).standardizedFileURL.path })

        // 2. Project artifacts.
        if !cancelled && groups.contains(.projects) {
            cancelled = findArtifacts(home: home, deep: deep, items: &items, skipped: &skipped, progress: progress)
        }

        // 3. Per-app folders.
        if !cancelled && groups.contains(.userCache) {
            cancelled = scanChildren(of: home.appendingPathComponent("Library/Caches"), label: "Library/Caches", skipCovered: covered,
                                     group: .userCache, tool: "App cache", risk: .caution, minimum: Self.childMinimumBytes,
                                     reason: "An app's cache folder. Apps normally rebuild these, but Orbit can't verify what this app stores. Quit the app first.",
                                     items: &items, progress: progress)
        }
        if !cancelled && groups.contains(.systemJunk) {
            cancelled = scanChildren(of: home.appendingPathComponent("Library/Logs"), label: "Library/Logs", skipCovered: covered,
                                     group: .systemJunk, tool: "App logs", risk: .regenerable, minimum: 1_000_000,
                                     reason: "Diagnostic logs. Apps recreate them as needed.", items: &items, progress: progress)
        }
        if !cancelled && groups.contains(.deep) && deep {
            cancelled = scanChildren(of: home.appendingPathComponent(".cache"), label: ".cache", skipCovered: covered,
                                     group: .deep, tool: "Tool cache", risk: .caution, minimum: Self.childMinimumBytes,
                                     reason: "A tool's cache under ~/.cache. Usually rebuildable, but Orbit can't verify what this tool stores.",
                                     items: &items, progress: progress)
            if !cancelled { cancelled = scanInstallers(home: home, items: &items) }
        }
        if !cancelled && groups.contains(.leftovers) {
            cancelled = scanLeftovers(home: home, items: &items, progress: progress)
        }

        result.items = items.sorted { $0.bytes > $1.bytes }
        result.skippedCount = skipped
        result.status = cancelled ? .cancelled : .completed
        result.finishedAt = Date()
        return result
    }

    private func scanChildren(of dir: URL, label: String, skipCovered: Set<String>, group: DevGroup, tool: String, risk: DevRisk,
                              minimum: Int64, reason: String, items: inout [DevItem],
                              progress: @Sendable (DevProgress) -> Void) -> Bool {
        guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else { return false }
        for child in children {
            if Task.isCancelled { return true }
            let name = child.lastPathComponent
            if name.hasPrefix("com.apple.") || name == ".DS_Store" || skipCovered.contains(child.standardizedFileURL.path) { continue }
            guard let identity = FileIdentity.current(at: child), identity.isDirectory else { continue }
            progress(DevProgress(itemsFound: items.count, current: "\(label)/\(name)"))
            guard let size = Self.directorySize(child) else { return true }
            guard size >= minimum else { continue }
            items.append(DevItem(url: child, title: name, tool: tool, group: group, risk: risk, reason: reason,
                                 bytes: size, modified: Self.modified(child), identity: identity, requiredMarker: nil))
        }
        return false
    }

    private func scanInstallers(home: URL, items: inout [DevItem]) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.staleInstallerDays, to: Date()) ?? Date()
        let types: Set<String> = ["dmg", "pkg", "iso", "xip"]
        guard let files = try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent("Downloads"),
                                                                       includingPropertiesForKeys: nil, options: []) else { return false }
        for file in files where types.contains(file.pathExtension.lowercased()) {
            if Task.isCancelled { return true }
            guard let identity = FileIdentity.current(at: file), identity.isRegularFile, identity.size >= 1_000_000 else { continue }
            let modified = Self.modified(file)
            guard modified <= cutoff else { continue }
            items.append(DevItem(
                url: file, title: file.lastPathComponent, tool: "Downloads", group: .deep, risk: .caution,
                reason: "Installer untouched for over \(Self.staleInstallerDays) days. It may be the only copy you have, so check before removing.",
                bytes: identity.size, modified: modified, identity: identity, requiredMarker: nil))
        }
        return false
    }

    // MARK: Leftovers

    static let leftoverFolders = [
        "Library/Application Support", "Library/Caches", "Library/Preferences", "Library/Containers",
        "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit", "Library/Application Scripts",
    ]

    /// Reverse-DNS names with at least three components, e.g. `com.vendor.App`.
    static func bundleIdentifier(fromEntryName name: String) -> String? {
        var id = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(suffix) { id = String(id.dropLast(suffix.count)) }
        guard id.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9_-]+){2,}$"#, options: .regularExpression) != nil else { return nil }
        guard !id.hasPrefix("com.apple.") && !id.hasPrefix("group.") else { return nil }
        return id
    }

    static func isInstalled(bundleID: String) -> Bool {
        let urls = LSCopyApplicationURLsForBundleIdentifier(bundleID as CFString, nil)?.takeRetainedValue() as? [URL]
        return !(urls ?? []).isEmpty
    }

    private func scanLeftovers(home: URL, items: inout [DevItem], progress: @Sendable (DevProgress) -> Void) -> Bool {
        var found: [DevItem] = []
        var cache: [String: Bool] = [:]
        for folder in Self.leftoverFolders {
            let dir = home.appendingPathComponent(folder)
            guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else { continue }
            for child in children {
                if Task.isCancelled { return true }
                guard let id = Self.bundleIdentifier(fromEntryName: child.lastPathComponent) else { continue }
                let installed = cache[id] ?? Self.isInstalled(bundleID: id)
                cache[id] = installed
                if installed { continue }
                guard let identity = FileIdentity.current(at: child), identity.isDirectory || identity.isRegularFile else { continue }
                progress(DevProgress(itemsFound: found.count, current: child.lastPathComponent))
                let size = identity.isDirectory ? (Self.directorySize(child) ?? 0) : identity.size
                found.append(DevItem(
                    url: child, title: child.lastPathComponent, tool: (folder as NSString).lastPathComponent, group: .leftovers,
                    risk: .caution,
                    reason: "Belongs to “\(id)”, which macOS can't find as an installed app. It may hold that app's settings or data, and the app might be on an external drive.",
                    bytes: size, modified: Self.modified(child), identity: identity, requiredMarker: nil))
            }
        }
        items.append(contentsOf: found.sorted { $0.bytes > $1.bytes }.prefix(300))
        return false
    }

    // MARK: Project artifacts

    private func findArtifacts(home: URL, deep: Bool, items: inout [DevItem], skipped: inout Int,
                               progress: @Sendable (DevProgress) -> Void) -> Bool {
        let rules = Dictionary(grouping: DevCatalog.artifactRules.filter { deep || !$0.deepOnly }, by: \.folderName)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        var skippedErrors = 0
        guard let enumerator = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
            errorHandler: { _, _ in skippedErrors += 1; return true }
        ) else { return false }

        let skipTop: Set<String> = ["Library", ".Trash", "Applications", "Movies", "Music", "Pictures"]
        var visited = 0
        var cancelled = false
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited % 256 == 0 && Task.isCancelled { cancelled = true; break }
            let name = url.lastPathComponent
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let level = enumerator.level
            if (level == 1 && skipTop.contains(name)) || name == ".git" || (name.hasPrefix(".") && !rules.keys.contains(name))
                || level > 10 {
                enumerator.skipDescendants(); continue
            }
            guard let candidates = rules[name] else { continue }
            let parent = url.deletingLastPathComponent()
            for rule in candidates {
                let base = rule.markerInside ? url : parent
                guard let marker = Self.findMarker(rule.markers, in: base) else { continue }
                enumerator.skipDescendants()
                guard let identity = FileIdentity.current(at: url), identity.isDirectory else { break }
                progress(DevProgress(itemsFound: items.count, current: "\(parent.lastPathComponent)/\(name)"))
                guard let size = Self.directorySize(url) else { return true }
                if size > 0 {
                    items.append(DevItem(
                        url: url, title: "\(parent.lastPathComponent)/\(name)", tool: rule.tool, group: .projects,
                        risk: .regenerable, reason: rule.reason, bytes: size, modified: Self.modified(url),
                        identity: identity, requiredMarker: rule.markerInside ? nil : marker
                    ))
                }
                break
            }
        }
        skipped += skippedErrors
        return cancelled
    }

    /// Finds the first marker present in `base`. A marker like `*.py` matches any file with that extension.
    static func findMarker(_ markers: [String], in base: URL) -> URL? {
        let fm = FileManager.default
        for marker in markers {
            if marker.hasPrefix("*.") {
                let ext = String(marker.dropFirst(2))
                if let match = (try? fm.contentsOfDirectory(atPath: base.path))?.first(where: { ($0 as NSString).pathExtension == ext }) {
                    return base.appendingPathComponent(match)
                }
            } else if fm.fileExists(atPath: base.appendingPathComponent(marker).path) {
                return base.appendingPathComponent(marker)
            }
        }
        return nil
    }

    /// Total allocated size of a folder tree without following symlinks. `nil` if cancelled.
    static func directorySize(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey], options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        var count = 0
        while let file = enumerator.nextObject() as? URL {
            count += 1
            if count % 512 == 0 && Task.isCancelled { return nil }
            if let v = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
               v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Moves reviewed folders and files to the Trash after revalidating each one.
nonisolated struct DevCleanupExecutor: Sendable {
    var trasher: Trashing = SystemTrasher()

    /// - Parameters:
    ///   - extraRoots: additional folders items may live in besides `home` (e.g. /Applications for the uninstaller).
    ///   - blocked: item id → reason; those items are skipped without touching them (e.g. the app is running).
    func execute(items: [DevItem], home: URL, extraRoots: [URL] = [], blocked: [String: String] = [:],
                 progress: (@Sendable (_ done: Int, _ total: Int, _ current: String) -> Void)? = nil) async -> DevCleanupReport {
        let work = Task.detached(priority: .userInitiated) { () -> DevCleanupReport in
            var results: [DevItemResult] = []
            for (index, item) in items.enumerated() {
                if Task.isCancelled {
                    results.append(DevItemResult(item: item, outcome: .skipped("Cancelled before this item was reached")))
                    continue
                }
                progress?(index, items.count, item.title)
                if let why = blocked[item.id] {
                    results.append(DevItemResult(item: item, outcome: .skipped(why)))
                    continue
                }
                var landed: URL?
                let outcome = process(item, home: home, extraRoots: extraRoots, trashedTo: &landed)
                results.append(DevItemResult(item: item, outcome: outcome, trashedURL: landed))
            }
            progress?(items.count, items.count, "")
            return DevCleanupReport(results: results)
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    func process(_ item: DevItem, home: URL, extraRoots: [URL] = []) -> CleanupOutcome {
        var landed: URL?
        return process(item, home: home, extraRoots: extraRoots, trashedTo: &landed)
    }

    func process(_ item: DevItem, home: URL, extraRoots: [URL] = [], trashedTo landed: inout URL?) -> CleanupOutcome {
        guard item.selectable else { return .skipped("Orbit only reports this item and never removes it") }
        if Exclusions.isExcluded(item.url) { return .skipped("In a folder you excluded in Settings") }
        let path = item.url.standardizedFileURL.path
        let roots = ([home] + extraRoots).map { $0.standardizedFileURL.path }
        guard roots.contains(where: { path.hasPrefix($0 + "/") }) else { return .skipped("Outside the folders Orbit may modify") }
        if let why = CleanupExecutor.protectionReason(for: item.url), !(item.group == .leftovers && item.url.pathExtension == "app") {
            return .skipped(why)
        }
        guard let now = FileIdentity.current(at: item.url) else { return .skipped("No longer exists at this location") }
        if item.identity.isRegularFile {
            guard now == item.identity else { return .skipped("Changed since the scan") }
        } else {
            guard now.isDirectory else { return .skipped("No longer a folder (it may be a link now)") }
            guard now.device == item.identity.device, now.inode == item.identity.inode else {
                return .skipped("Replaced since the scan")
            }
        }
        if let marker = item.requiredMarker, !FileManager.default.fileExists(atPath: marker.path) {
            return .skipped("Project file \(marker.lastPathComponent) is gone, so this may no longer be a build folder")
        }
        do {
            landed = try trasher.trashItem(item.url)
            return .completed
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
