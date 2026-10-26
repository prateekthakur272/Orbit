//
//  SpaceExplorerView.swift
//  Orbit
//

import SwiftUI

@Observable
final class SpaceExplorerModel {
    struct Entry: Identifiable { let id: String; let url: URL; let bytes: Int64; let isDirectory: Bool; var name: String { url.lastPathComponent } }

    private(set) var root: URL?
    private(set) var current: URL?
    private(set) var entries: [Entry] = []
    private(set) var loading = false
    private(set) var unreadable = false
    private var worker: Task<Void, Never>?
    private var generation = 0

    func choose(start: URL? = nil) {
        guard let url = FolderPicker.choose(message: "Choose a folder to explore. Orbit only reads it.", start: start) else { return }
        root = url
        load(url)
    }

    func open(_ url: URL) { load(url) }

    func use(_ url: URL) { root = url; load(url) }

    func up() {
        guard let current, let root, current.standardizedFileURL.path != root.standardizedFileURL.path else { return }
        load(current.deletingLastPathComponent())
    }

    var canGoUp: Bool { current != nil && current?.standardizedFileURL.path != root?.standardizedFileURL.path }

    private func load(_ dir: URL) {
        worker?.cancel()
        generation += 1
        let gen = generation
        current = dir
        entries = []
        unreadable = false
        loading = true
        worker = Task.detached(priority: .userInitiated) {
            guard let children = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else {
                await self.finish(gen, unreadable: true)
                return
            }
            for child in children {
                if Task.isCancelled { return }
                guard let identity = FileIdentity.current(at: child) else { continue }
                let bytes: Int64
                if identity.isDirectory { guard let size = DevScanner.directorySize(child) else { return }; bytes = size }
                else if identity.isRegularFile { bytes = identity.size } else { continue }
                let entry = Entry(id: child.path, url: child, bytes: bytes, isDirectory: identity.isDirectory)
                await self.append(entry, gen)
            }
            await self.finish(gen, unreadable: false)
        }
    }

    private func append(_ entry: Entry, _ gen: Int) {
        guard generation == gen else { return }
        Motion.run {
            entries.append(entry)
            entries.sort { $0.bytes > $1.bytes }
        }
    }

    private func finish(_ gen: Int, unreadable: Bool) {
        guard generation == gen else { return }
        self.unreadable = unreadable
        loading = false
    }
}

struct SpaceExplorerView: View {
    @Environment(SpaceExplorerModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "Space Explorer", subtitle: "See which folders and files use the most space",
                           symbol: "chart.pie.fill", trailing: AnyView(HStack {
                    Button("Choose Folder…") { model.choose() }
                    Button("Home Folder") { model.choose(start: DevCleanupModelHome.home) }
                }))
                if let current = model.current {
                    HStack {
                        Button("Up", systemImage: "chevron.up") { model.up() }.disabled(!model.canGoUp)
                        Text(current.path).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        if model.loading { ProgressView().controlSize(.small) }
                    }
                }
                Text("Read-only: nothing here is changed. Sizes are on-disk estimates for items Orbit can read.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            if model.current == nil {
                ContentUnavailableView {
                    Label("Explore a folder", systemImage: "chart.pie.fill")
                } description: { Text("Choose a folder to see a size breakdown of what's inside.") } actions: {
                    Button("Choose a Folder…") { model.choose() }.buttonStyle(.borderedProminent).tint(.teal)
                }
            } else if model.unreadable {
                ContentUnavailableView("Can't read this folder", systemImage: "lock.slash",
                                       description: Text("macOS didn't allow access. Choose a different folder."))
            } else if model.entries.isEmpty && !model.loading {
                ContentUnavailableView("Empty folder", systemImage: "folder")
            } else {
                let maxBytes = Double(max(model.entries.first?.bytes ?? 1, 1))
                List(model.entries) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(entry.isDirectory ? Color.teal : Color.secondary).frame(width: 22)
                        Text(entry.name).lineLimit(1).frame(minWidth: 160, alignment: .leading)
                        ProgressView(value: Double(entry.bytes), total: maxBytes).tint(.teal)
                            .animation(Motion.spring, value: entry.bytes)
                            .accessibilityHidden(true)
                        Text(SizeFormat.string(entry.bytes)).monospacedDigit().frame(width: 90, alignment: .trailing)
                        if entry.isDirectory { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                    }
                    .contentShape(Rectangle())
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    .onTapGesture { if entry.isDirectory { model.open(entry.url) } }
                    .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(entry.isDirectory ? "Opens this folder" : "")
                }
            }
        }
        .folderDrop { model.use($0) }
    }
}
