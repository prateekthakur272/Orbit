//
//  TrashService.swift
//  Orbit
//

import Foundation

nonisolated protocol Removing: Sendable {
    func remove(_ url: URL) throws
}

nonisolated struct PermanentRemover: Removing {
    func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
}

nonisolated struct TrashStatus: Sendable, Equatable {
    var itemCount: Int
    var bytes: Int64
}

nonisolated struct TrashEmptyResult: Sendable {
    var removed = 0
    var failed: [SkippedItem] = []
}

/// Inspects and empties the user's Trash. Only ever touches the top-level entries of `~/.Trash`.
nonisolated enum TrashService {
    static func trashURL(home: URL) -> URL { home.appendingPathComponent(".Trash") }

    nonisolated struct Entry: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let bytes: Int64
        let isDirectory: Bool
    }

    static func entries(home: URL) -> [Entry]? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: trashURL(home: home), includingPropertiesForKeys: nil, options: []
        ) else { return nil }
        return children.compactMap { child in
            guard let identity = FileIdentity.current(at: child) else { return nil }
            let bytes = identity.isDirectory ? (DevScanner.directorySize(child) ?? 0) : identity.size
            return Entry(name: child.lastPathComponent, bytes: bytes, isDirectory: identity.isDirectory)
        }.sorted { $0.bytes > $1.bytes }
    }

    /// `nil` when the Trash can't be read (e.g. Full Disk Access is missing).
    static func status(home: URL) -> TrashStatus? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: trashURL(home: home), includingPropertiesForKeys: nil, options: []
        ) else { return nil }
        var total: Int64 = 0
        for child in children {
            guard let identity = FileIdentity.current(at: child) else { continue }
            if identity.isDirectory { total += DevScanner.directorySize(child) ?? 0 } else { total += identity.size }
        }
        return TrashStatus(itemCount: children.count, bytes: total)
    }

    /// Permanently removes everything currently in the Trash. Callers must have confirmed with the user.
    static func empty(home: URL, remover: Removing = PermanentRemover()) -> TrashEmptyResult {
        var result = TrashEmptyResult()
        let trash = trashURL(home: home)
        guard let children = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil, options: []) else {
            result.failed.append(SkippedItem(path: trash.path, reason: "Can't read the Trash. Grant Full Disk Access to Orbit and try again."))
            return result
        }
        for child in children {
            do { try remover.remove(child); result.removed += 1 } catch {
                result.failed.append(SkippedItem(path: child.lastPathComponent, reason: error.localizedDescription))
            }
        }
        return result
    }
}
