//
//  HistoryStore.swift
//  Orbit
//

import Foundation
import Observation

/// One finished cleanup operation, kept on this Mac only.
nonisolated struct HistoryEntry: Codable, Identifiable, Sendable {
    struct Line: Codable, Sendable {
        let title: String
        let path: String
        let bytes: Int64
        /// "moved", "skipped" or "failed"
        let status: String
        let detail: String?
    }

    let id: UUID
    let date: Date
    let source: String
    let lines: [Line]

    var moved: [Line] { lines.filter { $0.status == "moved" } }
    var movedBytes: Int64 { moved.reduce(0) { $0 + $1.bytes } }
    var problemCount: Int { lines.count - moved.count }

    init(source: String, report: DevCleanupReport) {
        id = UUID()
        date = Date()
        self.source = source
        lines = report.results.map { r in
            switch r.outcome {
            case .completed: Line(title: r.item.title, path: r.item.url.path, bytes: r.item.bytes, status: "moved", detail: nil)
            case .skipped(let why): Line(title: r.item.title, path: r.item.url.path, bytes: r.item.bytes, status: "skipped", detail: why)
            case .failed(let why): Line(title: r.item.title, path: r.item.url.path, bytes: r.item.bytes, status: "failed", detail: why)
            }
        }
    }
}

/// Local-only operation log. Nothing here is ever uploaded.
@Observable
final class HistoryModel {
    static let shared = HistoryModel()

    private(set) var entries: [HistoryEntry] = []
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL
        load()
    }

    private static var defaultURL: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Orbit", isDirectory: true).appendingPathComponent("history.json")
    }

    var totalMovedBytes: Int64 { entries.reduce(0) { $0 + $1.movedBytes } }

    func record(source: String, report: DevCleanupReport) {
        guard !report.results.isEmpty else { return }
        entries.insert(HistoryEntry(source: source, report: report), at: 0)
        if entries.count > 200 { entries.removeLast(entries.count - 200) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Folders the user has told Orbit to leave alone. Honoured by scanning and, again, right before any move to the Trash.
nonisolated enum Exclusions {
    static let key = "excludedPaths"

    static var paths: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func isExcluded(_ url: URL, in list: [String] = Exclusions.paths) -> Bool {
        let path = url.standardizedFileURL.path
        return list.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
