//
//  Models.swift
//  Orbit
//

import Foundation
import UniformTypeIdentifiers

/// Snapshot of a file's identity taken with `lstat`, used to detect changes between scan and cleanup.
nonisolated struct FileIdentity: Hashable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let isRegularFile: Bool
    let isDirectory: Bool

    /// Reads the identity of the item at `url` without following symbolic links.
    static func current(at url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return FileIdentity(
            device: info.st_dev,
            inode: info.st_ino,
            size: info.st_size,
            modifiedSeconds: info.st_mtimespec.tv_sec,
            modifiedNanoseconds: info.st_mtimespec.tv_nsec,
            isRegularFile: (info.st_mode & S_IFMT) == S_IFREG,
            isDirectory: (info.st_mode & S_IFMT) == S_IFDIR
        )
    }
}

nonisolated enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case video = "Video", image = "Images", audio = "Audio"
    case archive = "Archives & Disk Images", document = "Documents", other = "Other"
    var id: String { rawValue }

    static func classify(pathExtension ext: String) -> FileKind {
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .spreadsheet)
            || type.conforms(to: .presentation) { return .document }
        return .other
    }
}

nonisolated struct ScannedFile: Identifiable, Hashable, Sendable {
    /// Unique within one scan (the path). Not a permanent identity; see `identity`.
    var id: String { url.path }
    let url: URL
    let name: String
    let kind: FileKind
    /// Size on disk (allocated); falls back to logical size when unavailable.
    let allocatedSize: Int64
    let logicalSize: Int64
    let modified: Date
    let identity: FileIdentity
}

nonisolated struct ScanProgress: Sendable {
    var filesExamined = 0
    var bytesExamined: Int64 = 0
    var currentFolder = ""
}

nonisolated struct SkippedItem: Hashable, Sendable {
    let path: String
    let reason: String
}

nonisolated enum ScanStatus: Equatable, Sendable {
    case completed
    case cancelled
    case failed(String)

    var isPartial: Bool { self != .completed }
}

nonisolated struct ScanResult: Sendable {
    let scope: URL
    let startedAt: Date
    var finishedAt: Date
    var status: ScanStatus
    var files: [ScannedFile]
    var filesExamined: Int
    var bytesExamined: Int64
    var skippedCount: Int
    /// A bounded sample of skipped items (for display); `skippedCount` is the true total.
    var skippedSample: [SkippedItem]
    /// True when more candidate files were found than `files` retains.
    var truncated: Bool
}

nonisolated enum CleanupOutcome: Equatable, Sendable {
    case completed
    case skipped(String)
    case failed(String)
}

nonisolated struct CleanupItemResult: Identifiable, Sendable {
    var id: String { file.id }
    let file: ScannedFile
    let outcome: CleanupOutcome
}

nonisolated struct CleanupReport: Sendable {
    let results: [CleanupItemResult]
    var completed: [CleanupItemResult] { results.filter { $0.outcome == .completed } }
    var skipped: [CleanupItemResult] { results.filter { if case .skipped = $0.outcome { true } else { false } } }
    var failed: [CleanupItemResult] { results.filter { if case .failed = $0.outcome { true } else { false } } }
    /// Estimate only: sum of sizes of items successfully moved to Trash.
    var estimatedMovedBytes: Int64 { completed.reduce(0) { $0 + $1.file.allocatedSize } }
}

nonisolated enum SizeFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
