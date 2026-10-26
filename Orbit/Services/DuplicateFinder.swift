//
//  DuplicateFinder.swift
//  Orbit
//

import CryptoKit
import Foundation

nonisolated struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let fileSize: Int64
    var files: [ScannedFile]
    /// Space that would be freed by keeping one file.
    var wastedBytes: Int64 { fileSize * Int64(max(files.count - 1, 0)) }
}

nonisolated struct DuplicateResult: Sendable {
    let scope: URL
    var status: ScanStatus
    var groups: [DuplicateGroup]
    var filesExamined: Int
    var finishedAt: Date
}

nonisolated struct DuplicateProgress: Sendable {
    var stage = "Listing files"
    var done = 0
}

/// Confirms duplicates by content: group by size, then a hash of the first 64 KB, then a full SHA-256.
/// Metadata alone never establishes a duplicate, and hard links to one file are not reported.
nonisolated struct DuplicateFinder: Sendable {
    var minimumSize: Int64 = 1_000_000
    var headBytes = 64 * 1024

    func find(root: URL, progress: @escaping @Sendable (DuplicateProgress) -> Void) async -> DuplicateResult {
        let task = Task.detached(priority: .userInitiated) { run(root: root, progress: progress) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func run(root: URL, progress: @Sendable (DuplicateProgress) -> Void) -> DuplicateResult {
        var result = DuplicateResult(scope: root, status: .completed, groups: [], filesExamined: 0, finishedAt: Date())
        guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else {
            result.status = .failed("Orbit can't read this folder. Choose it again, or pick a different folder.")
            return result
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                               options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else {
            result.status = .failed("Could not start reading this folder.")
            return result
        }

        // Stage 0: collect candidates by logical size, skipping symlinks and duplicate inodes (hard links).
        var bySize: [Int64: [ScannedFile]] = [:]
        var seenInodes = Set<String>()
        var examined = 0
        while let url = enumerator.nextObject() as? URL {
            examined += 1
            if examined % 256 == 0 {
                if Task.isCancelled { result.status = .cancelled; result.filesExamined = examined; return result }
                progress(DuplicateProgress(stage: "Listing files", done: examined))
            }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true, v.isRegularFile == true,
                  let size = v.fileSize.map(Int64.init), size >= minimumSize,
                  let identity = FileIdentity.current(at: url), identity.isRegularFile else { continue }
            guard seenInodes.insert("\(identity.device):\(identity.inode)").inserted else { continue }
            bySize[size, default: []].append(ScannedFile(
                url: url, name: url.lastPathComponent, kind: FileKind.classify(pathExtension: url.pathExtension),
                allocatedSize: Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0), logicalSize: size,
                modified: v.contentModificationDate ?? .distantPast, identity: identity))
        }
        result.filesExamined = examined

        // Stage 1 & 2: narrow by head hash, confirm with full hash.
        var hashed = 0
        var groups: [DuplicateGroup] = []
        for (size, files) in bySize where files.count > 1 {
            var byHead: [String: [ScannedFile]] = [:]
            for file in files {
                if Task.isCancelled { result.status = .cancelled; result.groups = groups; return result }
                guard let head = Self.hash(of: file.url, limit: headBytes) else { continue }
                byHead[head, default: []].append(file)
                hashed += 1
                if hashed % 20 == 0 { progress(DuplicateProgress(stage: "Comparing contents", done: hashed)) }
            }
            for (_, candidates) in byHead where candidates.count > 1 {
                var byFull: [String: [ScannedFile]] = [:]
                for file in candidates {
                    if Task.isCancelled { result.status = .cancelled; result.groups = groups; return result }
                    guard let full = Self.hash(of: file.url, limit: nil) else { continue }
                    byFull[full, default: []].append(file)
                }
                for (digest, same) in byFull where same.count > 1 {
                    groups.append(DuplicateGroup(id: digest, fileSize: size, files: same.sorted { $0.modified < $1.modified }))
                }
            }
        }
        result.groups = groups.sorted { $0.wastedBytes > $1.wastedBytes }
        result.finishedAt = Date()
        return result
    }

    /// SHA-256 of the file, or of its first `limit` bytes. `nil` if unreadable or cancelled.
    static func hash(of url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit
        let chunk = 1 << 20
        while true {
            if Task.isCancelled { return nil }
            let want = min(chunk, remaining ?? chunk)
            if want == 0 { break }
            guard let data = try? handle.read(upToCount: want), !data.isEmpty else { break }
            hasher.update(data: data)
            if let r = remaining { remaining = r - data.count }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
