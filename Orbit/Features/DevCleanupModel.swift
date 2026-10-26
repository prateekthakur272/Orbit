//
//  DevCleanupModel.swift
//  Orbit
//

import AppKit
import Observation

enum DevSort: String, CaseIterable, Identifiable {
    case size = "Size", name = "Name", age = "Oldest first"
    var id: String { rawValue }
}

@Observable
final class DevCleanupModel {
    enum Phase { case idle, scanning, finished }

    private(set) var home: URL?
    private(set) var phase: Phase = .idle
    private(set) var result: DevScanResult?
    private(set) var progress = DevProgress()
    private(set) var startedAt = Date()
    private(set) var isCleaning = false
    var accessMessage: String?
    var searchText = ""
    var deepScan = false
    var sort = DevSort.size
    var minimumAgeDays = 0
    private(set) var trash: TrashStatus?
    private(set) var trashEntries: [TrashService.Entry] = []
    private(set) var trashReadable = true
    private(set) var scannedGroups = Set<DevGroup>()
    var emptyTrashSummary: String?
    var selection = Set<String>()
    var showingReview = false
    var report: DevCleanupReport?
    /// Live progress while items are being moved to the Trash.
    private(set) var cleanProgress: (done: Int, total: Int, current: String)?
    private var cleanTask: Task<Void, Never>?
    private var task: Task<Void, Never>?
    private var accessing = false

    static var realHome: URL {
        URL(fileURLWithPath: getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory())
    }

    var items: [DevItem] { result?.items ?? [] }
    /// Items in the developer categories only (what the Developer Cleanup overview shows).
    var developerItems: [DevItem] { items.filter { $0.group.isDeveloper } }

    /// Items passing the search and age filters.
    var visibleItems: [DevItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let cutoff = Calendar.current.date(byAdding: .day, value: -minimumAgeDays, to: Date()) ?? Date()
        let filtered = items.filter { item in
            (minimumAgeDays == 0 || item.modified <= cutoff)
                && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
                    || item.tool.localizedCaseInsensitiveContains(query) || item.url.path.localizedCaseInsensitiveContains(query))
        }
        switch sort {
        case .size: return filtered.sorted { $0.bytes > $1.bytes }
        case .name: return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .age: return filtered.sorted { $0.modified < $1.modified }
        }
    }

    /// Selects every visible regenerable item. The user still reviews the list before anything moves.
    func selectVisibleRegenerable() {
        selection.formUnion(visibleItems.filter { $0.risk == .regenerable && $0.selectable }.map(\.id))
    }

    func refreshTrash() {
        guard let home else { return }
        Task {
            let entries = await Task.detached { TrashService.entries(home: home) }.value
            trashEntries = entries ?? []
            trash = entries.map { TrashStatus(itemCount: $0.count, bytes: $0.reduce(0) { $0 + $1.bytes }) }
            trashReadable = entries != nil
        }
    }

    /// Permanent. The view must have shown a separate confirmation first.
    func emptyTrash() {
        guard let home, !isCleaning else { return }
        isCleaning = true
        Task {
            let outcome = await Task.detached { TrashService.empty(home: home) }.value
            ToastCenter.shared.show("Trash emptied: \(outcome.removed) item(s) removed", symbol: "trash.fill")
            emptyTrashSummary = "Removed \(outcome.removed) item(s) permanently."
                + (outcome.failed.isEmpty ? "" : " \(outcome.failed.count) couldn't be removed: \(outcome.failed.first?.reason ?? "")")
            isCleaning = false
            refreshTrash()
        }
    }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var selectedItems: [DevItem] { items.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }

    func items(in group: DevGroup) -> [DevItem] { items.filter { $0.group == group } }
    /// True once any scan has produced a result that covered `group` (even if it found nothing).
    func hasScanned(_ group: DevGroup) -> Bool { scannedGroups.contains(group) }
    func bytes(in group: DevGroup) -> Int64 { items(in: group).reduce(0) { $0 + $1.bytes } }

    func setSelected(_ item: DevItem, _ on: Bool) {
        if on && item.selectable { selection.insert(item.id) } else { selection.remove(item.id) }
    }

    /// The sandbox only reads what the user selects, so these folders need the home folder to be chosen once.
    @discardableResult
    func ensureAccess() -> Bool {
        if home != nil { return true }
        let panel = NSOpenPanel()
        panel.directoryURL = Self.realHome
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.prompt = "Grant Access"
        panel.message = "Select your home folder (\(Self.realHome.lastPathComponent)) so Orbit can look for caches and leftovers. Orbit only reads and, after your review, moves items to the Trash."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard url.standardizedFileURL.path == Self.realHome.standardizedFileURL.path else {
            accessMessage = "Please select your home folder: \(Self.realHome.path)"
            return false
        }
        accessMessage = nil
        accessing = url.startAccessingSecurityScopedResource()
        home = url
        return true
    }

    func grantAccessAndScan(groups: Set<DevGroup> = Set(DevGroup.developerGroups)) {
        guard ensureAccess() else { return }
        scan(groups: groups)
    }

    /// Scans only `groups`; results for other groups from earlier scans are kept.
    func scan(groups: Set<DevGroup>) {
        guard let home, phase != .scanning else { return }
        Motion.run { phase = .scanning }
        progress = DevProgress()
        startedAt = Date()
        let deep = deepScan
        task = Task {
            let scanned = await DevScanner().scan(home: home, groups: groups, deep: deep) { update in
                Task { @MainActor in if self.phase == .scanning { self.progress = update } }
            }
            var merged = scanned
            let excludedPaths = Exclusions.paths
            merged.items.removeAll { Exclusions.isExcluded($0.url, in: excludedPaths) }
            if case .failed = scanned.status {} else {
                merged.items = (result?.items ?? []).filter { !groups.contains($0.group) } + scanned.items
                merged.items.sort { $0.bytes > $1.bytes }
            }
            selection = selection.intersection(Set(merged.items.map(\.id)))
            Motion.run {
                result = merged
                if scanned.status == .completed { scannedGroups.formUnion(groups) }
                phase = .finished
            }
            if scanned.status == .completed {
                ToastCenter.shared.show("Scan complete: \(SizeFormat.string(merged.items.filter { groups.contains($0.group) }.reduce(0) { $0 + $1.bytes })) found", symbol: "sparkle.magnifyingglass")
            }
            refreshTrash()
        }
    }

    func cancel() { task?.cancel() }

    func executeCleanup() {
        guard !isCleaning, let home, !selectedItems.isEmpty else { return }
        let chosen = selectedItems
        isCleaning = true
        cleanProgress = (0, chosen.count, "")
        cleanTask = Task {
            let outcome = await DevCleanupExecutor().execute(items: chosen, home: home) { done, total, current in
                Task { @MainActor in self.cleanProgress = (done, total, current) }
            }
            let gone = Set(outcome.results.filter {
                if $0.outcome == .completed { return true }
                if case .skipped(let why) = $0.outcome, why.hasPrefix("No longer exists") { return true }
                return false
            }.map(\.id))
            Motion.run {
                result?.items.removeAll { gone.contains($0.id) }
                selection.subtract(gone)
            }
            report = outcome
            HistoryModel.shared.record(source: "Cleanup", report: outcome)
            ToastCenter.shared.show("Moved \(outcome.completed.count) item(s) to the Trash (about \(SizeFormat.string(outcome.estimatedMovedBytes)))")
            showingReview = false
            isCleaning = false
            cleanProgress = nil
            refreshTrash()
        }
    }

    /// Stops after the item in flight; everything not yet reached is reported as skipped.
    func cancelCleanup() { cleanTask?.cancel() }

    /// Moves items from a finished cleanup back to where they were. Never overwrites anything that now exists there.
    func putBack(_ report: DevCleanupReport) {
        var restored: [DevItem] = []
        var blocked = 0
        for r in report.completed {
            guard let trashed = r.trashedURL, FileManager.default.fileExists(atPath: trashed.path) else { blocked += 1; continue }
            guard !FileManager.default.fileExists(atPath: r.item.url.path) else { blocked += 1; continue }
            do {
                try FileManager.default.moveItem(at: trashed, to: r.item.url)
                restored.append(r.item)
            } catch { blocked += 1 }
        }
        Motion.run {
            result?.items.append(contentsOf: restored.filter { item in !(result?.items.contains { $0.id == item.id } ?? true) })
            result?.items.sort { $0.bytes > $1.bytes }
        }
        var message = "Put back \(restored.count) item(s)"
        if blocked > 0 { message += "; \(blocked) could not be restored (already moved, emptied, or something is in the way)" }
        ToastCenter.shared.show(message, symbol: "arrow.uturn.backward")
        self.report = nil
        refreshTrash()
    }

    /// Adds the item's folder to the user's exclusions and drops it from the current results.
    func exclude(_ item: DevItem) {
        var paths = Exclusions.paths
        let path = item.url.standardizedFileURL.path
        if !paths.contains(path) { paths.append(path); Exclusions.paths = paths }
        Motion.run {
            result?.items.removeAll { $0.id == item.id }
            selection.remove(item.id)
        }
        ToastCenter.shared.show("Orbit will leave \(item.title) alone. Manage this in Settings.", symbol: "hand.raised")
    }

    func reveal(_ item: DevItem) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
}
