//
//  FileScanner.swift
//  Orbit
//

import Foundation

/// Read-only scanner. Never modifies the file system.
nonisolated struct FileScanner: Sendable {
    /// Files smaller than this are counted but not retained.
    var minimumRetainedSize: Int64 = 1_000_000
    var maxRetainedFiles = 5_000
    private let maxSkippedSample = 200

    /// System and virtual locations never descended into (sealed system volume, devices, other mounts, swap).
    static let excludedPaths: Set<String> = [
        "/System", "/Volumes", "/dev", "/usr", "/bin", "/sbin", "/cores",
        "/private/var/vm", "/private/etc", "/.Spotlight-V100", "/.fseventsd",
    ]

    func scan(root: URL, progress: @escaping @Sendable (ScanProgress) -> Void) async -> ScanResult {
        let task = Task.detached(priority: .userInitiated) {
            scanSynchronously(root: root, progress: progress)
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func scanSynchronously(root: URL, progress: @Sendable (ScanProgress) -> Void) -> ScanResult {
        let started = Date()
        var result = ScanResult(
            scope: root, startedAt: started, finishedAt: started, status: .completed,
            files: [], filesExamined: 0, bytesExamined: 0, skippedCount: 0, skippedSample: [], truncated: false
        )

        // Distinguish "could not scan" from "nothing found".
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: root.path)
        } catch {
            result.status = .failed("Orbit can't read this folder (\(error.localizedDescription)). Choose it again, or pick a different folder.")
            result.finishedAt = Date()
            return result
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey,
        ]
        var skippedCount = 0
        var sample: [SkippedItem] = []
        func skip(_ path: String, _ reason: String) {
            skippedCount += 1
            if sample.count < maxSkippedSample { sample.append(SkippedItem(path: path, reason: reason)) }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [],
            errorHandler: { url, error in
                skip(url.path, error.localizedDescription)
                return true
            }
        ) else {
            result.status = .failed("Could not start reading this folder.")
            result.finishedAt = Date()
            return result
        }

        var kept: [ScannedFile] = []
        var examined = 0
        var bytes: Int64 = 0
        var truncated = false
        var cancelled = false

        while let item = enumerator.nextObject() as? URL {
            if examined % 256 == 0 && Task.isCancelled { cancelled = true; break }
            if Self.excludedPaths.contains(item.path) { enumerator.skipDescendants(); continue }
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else {
                skip(item.path, "Metadata unavailable")
                continue
            }
            // Symbolic links are never followed or listed.
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            if let status = values.ubiquitousItemDownloadingStatus, status == .notDownloaded {
                skip(item.path, "Cloud placeholder (not downloaded)")
                continue
            }

            examined += 1
            let logical = Int64(values.fileSize ?? 0)
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            bytes += allocated

            if allocated >= minimumRetainedSize, let identity = FileIdentity.current(at: item) {
                kept.append(ScannedFile(
                    url: item, name: item.lastPathComponent,
                    kind: FileKind.classify(pathExtension: item.pathExtension),
                    allocatedSize: allocated, logicalSize: logical,
                    modified: values.contentModificationDate ?? .distantPast, identity: identity
                ))
                if kept.count > maxRetainedFiles * 2 {
                    kept.sort { $0.allocatedSize > $1.allocatedSize }
                    kept.removeLast(kept.count - maxRetainedFiles)
                    truncated = true
                }
            }

            if examined % 500 == 0 {
                progress(ScanProgress(filesExamined: examined, bytesExamined: bytes,
                                      currentFolder: item.deletingLastPathComponent().lastPathComponent))
            }
        }

        kept.sort { $0.allocatedSize > $1.allocatedSize }
        if kept.count > maxRetainedFiles {
            kept.removeLast(kept.count - maxRetainedFiles)
            truncated = true
        }
        progress(ScanProgress(filesExamined: examined, bytesExamined: bytes, currentFolder: ""))

        result.files = kept
        result.filesExamined = examined
        result.bytesExamined = bytes
        result.skippedCount = skippedCount
        result.skippedSample = sample
        result.truncated = truncated
        result.status = cancelled ? .cancelled : .completed
        result.finishedAt = Date()
        return result
    }
}
