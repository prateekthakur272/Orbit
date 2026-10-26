//
//  CleanupExecutor.swift
//  Orbit
//

import Foundation

nonisolated protocol Trashing: Sendable {
    func trash(_ url: URL) throws
    /// Same as `trash(_:)`, also returning where the item landed so it can be put back.
    func trashItem(_ url: URL) throws -> URL?
}

extension Trashing {
    func trashItem(_ url: URL) throws -> URL? {
        try trash(url)
        return nil
    }
}

nonisolated struct SystemTrasher: Trashing {
    func trash(_ url: URL) throws {
        _ = try trashItem(url)
    }

    func trashItem(_ url: URL) throws -> URL? {
        var landed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
        return landed as URL?
    }
}

/// Moves reviewed files to the Trash. Each item is revalidated immediately before acting;
/// anything that moved, changed, or is no longer a plain file is skipped, never deleted.
nonisolated struct CleanupExecutor: Sendable {
    var trasher: Trashing = SystemTrasher()

    func execute(files: [ScannedFile], scope: URL) async -> CleanupReport {
        await Task.detached(priority: .userInitiated) {
            CleanupReport(results: files.map { file in
                CleanupItemResult(file: file, outcome: process(file, scope: scope))
            })
        }.value
    }

    /// System locations and app-bundle contents are never cleanup candidates.
    static func protectionReason(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        for prefix in FileScanner.excludedPaths where path == prefix || path.hasPrefix(prefix + "/") {
            return "Protected system location"
        }
        if url.pathComponents.contains(where: { $0.hasSuffix(".app") }) {
            return "Inside an app bundle; removing it could break the app"
        }
        return nil
    }

    func process(_ file: ScannedFile, scope: URL) -> CleanupOutcome {
        let scopePath = scope.standardizedFileURL.path
        guard file.url.standardizedFileURL.path.hasPrefix(scopePath.hasSuffix("/") ? scopePath : scopePath + "/") else {
            return .skipped("Outside the scanned folder")
        }
        if let why = Self.protectionReason(for: file.url) { return .skipped(why) }
        guard let now = FileIdentity.current(at: file.url) else {
            return .skipped("No longer exists at this location")
        }
        guard now.isRegularFile else { return .skipped("No longer a regular file") }
        guard now == file.identity else { return .skipped("Changed since the scan") }
        do {
            try trasher.trash(file.url)
            return .completed
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
