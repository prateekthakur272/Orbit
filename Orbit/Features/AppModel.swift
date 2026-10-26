//
//  AppModel.swift
//  Orbit
//

import AppKit
import Observation

struct VolumeInfo {
    var name: String?
    var total: Int64?
    /// Free space right now, excluding purgeable.
    var available: Int64?
    /// Free space macOS could make available on demand (includes purgeable).
    var availableForImportantUsage: Int64?
    var purgeable: Int64? {
        guard let available, let availableForImportantUsage else { return nil }
        return max(availableForImportantUsage - available, 0)
    }
    var used: Int64? {
        guard let total, let availableForImportantUsage else { return nil }
        return max(total - availableForImportantUsage, 0)
    }
}

@Observable
final class AppModel {
    enum Phase { case idle, scanning, finished }
    enum Section: Hashable {
        case smartCare, protection, performance
        case uninstaller, appUpdates
        case spaceExplorer, duplicates, similarPhotos
        /// Cleanup, developer and leftover categories (all share one scan model). `nil` is the developer overview.
        case group(DevGroup?)
        case trashBins, largeFiles, history, settings
    }

    // Scope & scan
    private(set) var scope: URL?
    private(set) var phase: Phase = .idle
    private(set) var result: ScanResult?
    private(set) var progress = ScanProgress()
    private(set) var scanStartedAt = Date()
    private(set) var volume = VolumeInfo()
    private var scanTask: Task<Void, Never>?
    private var accessingScope = false

    // Results presentation
    var selection = Set<String>()
    var thresholdBytes: Int64 = 100_000_000
    var searchText = ""
    var section: Section = .smartCare
    var kindFilter: FileKind?
    var minimumAgeDays = 0
    var sortOrder = [KeyPathComparator(\ScannedFile.allocatedSize, order: .reverse)]

    // Cleanup
    var showingReview = false
    private(set) var isCleaning = false
    var report: CleanupReport?

    init() { refreshVolume() }

    // MARK: Volume

    func refreshVolume() {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        volume = VolumeInfo(
            name: values?.volumeName,
            total: values?.volumeTotalCapacity.map(Int64.init),
            available: values?.volumeAvailableCapacity.map(Int64.init),
            availableForImportantUsage: values?.volumeAvailableCapacityForImportantUsage
        )
    }

    // MARK: Scope

    func chooseFolder() { _ = pickFolder(startingAt: nil, message: nil) }

    @discardableResult
    private func pickFolder(startingAt start: URL?, message: String?) -> Bool {
        let panel = NSOpenPanel()
        panel.directoryURL = start
        panel.showsHiddenFiles = start != nil
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = message ?? "Choose a folder for Orbit to scan. Orbit only reads inside the folder you pick."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        setScope(url)
        return true
    }

    private func setScope(_ url: URL) {
        guard phase != .scanning else { return }
        if accessingScope { scope?.stopAccessingSecurityScopedResource() }
        accessingScope = url.startAccessingSecurityScopedResource()
        scope = url
        result = nil
        selection = []
        phase = .idle
    }

    var isWholeMac: Bool { scope?.path == "/" }

    /// Whether this process can read TCC-protected locations (Full Disk Access).
    var hasFullDiskAccess: Bool {
        guard let home = getpwuid(getuid()).flatMap({ String(cString: $0.pointee.pw_dir) }) else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: home + "/Library/Safari")) != nil
    }

    /// The sandbox only grants read access to what the user selects, so the whole disk is granted by picking it.
    func scanEntireMac() {
        guard phase != .scanning else { return }
        let granted = pickFolder(
            startingAt: URL(fileURLWithPath: "/"),
            message: "To scan your whole Mac, select the startup disk (Macintosh HD) and click Choose."
        )
        guard granted else { return }
        section = .largeFiles
        startScan()
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Scan

    func startScan() {
        guard let scope, phase != .scanning else { return }
        phase = .scanning
        progress = ScanProgress()
        scanStartedAt = Date()
        selection = []
        scanTask = Task {
            let scanned = await FileScanner().scan(root: scope) { update in
                Task { @MainActor in self.applyProgress(update) }
            }
            result = scanned
            phase = .finished
            refreshVolume()
        }
    }

    private func applyProgress(_ update: ScanProgress) {
        if phase == .scanning { progress = update }
    }

    /// Used by drag and drop.
    func use(_ url: URL) {
        guard phase != .scanning else { return }
        setScope(url)
        section = .largeFiles
        startScan()
    }

    func cancelScan() { scanTask?.cancel() }

    // MARK: Visible rows

    var visibleFiles: [ScannedFile] {
        guard let files = result?.files else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return files
            .filter { $0.allocatedSize >= thresholdBytes }
            .filter { kindFilter == nil || $0.kind == kindFilter }
            .filter { minimumAgeDays == 0 || $0.modified <= (Calendar.current.date(byAdding: .day, value: -minimumAgeDays, to: Date()) ?? Date()) }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted(using: sortOrder)
    }

    var selectedFiles: [ScannedFile] {
        (result?.files ?? []).filter { selection.contains($0.id) }.sorted { $0.allocatedSize > $1.allocatedSize }
    }

    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.allocatedSize } }

    func isSelected(_ file: ScannedFile) -> Bool { selection.contains(file.id) }

    func setSelected(_ file: ScannedFile, _ on: Bool) {
        if on { selection.insert(file.id) } else { selection.remove(file.id) }
    }

    func reveal(_ file: ScannedFile) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    // MARK: Cleanup

    func executeCleanup() {
        guard !isCleaning, let scope, !selectedFiles.isEmpty else { return }
        let files = selectedFiles
        isCleaning = true
        Task {
            let outcome = await CleanupExecutor().execute(files: files, scope: scope)
            // Drop only what actually left the scan results.
            let gone = Set(outcome.results.filter { r in
                if case .completed = r.outcome { return true }
                if case .skipped(let why) = r.outcome, why.hasPrefix("No longer exists") { return true }
                return false
            }.map(\.id))
            Motion.run {
                result?.files.removeAll { gone.contains($0.id) }
                selection.subtract(gone)
            }
            report = outcome
            ToastCenter.shared.show("Moved \(outcome.completed.count) file(s) to the Trash")
            showingReview = false
            isCleaning = false
            refreshVolume()
        }
    }
}
