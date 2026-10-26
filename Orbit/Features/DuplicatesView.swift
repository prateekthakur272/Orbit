//
//  DuplicatesView.swift
//  Orbit
//

import SwiftUI

@Observable
final class DuplicatesModel {
    private(set) var scope: URL?
    private(set) var result: DuplicateResult?
    private(set) var scanning = false
    private(set) var progress = DuplicateProgress()
    var minimumMB = 1
    let runner = FileCleanupRunner()
    private var task: Task<Void, Never>?

    func choose() {
        guard !scanning, let url = FolderPicker.choose(message: "Choose a folder to search for duplicate files.") else { return }
        scope = url; result = nil; runner.selection = []
    }

    func use(_ url: URL) {
        guard !scanning else { return }
        scope = url; result = nil; runner.selection = []
    }

    func scan() {
        guard let scope, !scanning else { return }
        scanning = true
        runner.selection = []
        var finder = DuplicateFinder()
        finder.minimumSize = Int64(minimumMB) * 1_000_000
        task = Task {
            let found = await finder.find(root: scope) { update in Task { @MainActor in self.progress = update } }
            Motion.run { result = found; scanning = false }
        }
    }

    func cancel() { task?.cancel() }

    var allFiles: [ScannedFile] { result?.groups.flatMap(\.files) ?? [] }
    var selectedFiles: [ScannedFile] { allFiles.filter { runner.selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.allocatedSize } }
    /// Groups where every copy is selected. Orbit refuses to review these: at least one copy must stay.
    var fullySelectedGroups: [DuplicateGroup] {
        (result?.groups ?? []).filter { g in g.files.allSatisfy { runner.selection.contains($0.id) } }
    }

    func keepOldest(in group: DuplicateGroup) {
        runner.selection.subtract(group.files.map(\.id))
        runner.selection.formUnion(group.files.dropFirst().map(\.id))
    }

    func removeGone(_ gone: Set<String>) {
        guard var r = result else { return }
        r.groups = r.groups.compactMap { g in
            var g = g
            g.files.removeAll { gone.contains($0.id) }
            return g.files.count > 1 ? g : nil
        }
        result = r
    }
}

struct DuplicatesView: View {
    @Environment(DuplicatesModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var runner = model.runner
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "Duplicate Finder", subtitle: "Files with identical contents in a folder you choose",
                           symbol: "doc.on.doc.fill", trailing: AnyView(controls))
                if model.scanning {
                    ScanActivityBanner(title: model.progress.stage, detail: model.scope?.path ?? "", count: model.progress.done)
                }
                if let r = model.result, !model.scanning {
                    switch r.status {
                    case .completed:
                        Label("Found \(r.groups.count) group(s). Copies are confirmed identical by content hash.", systemImage: "checkmark.circle")
                    case .cancelled: Label("Scan cancelled. Results are partial.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    case .failed(let m): Label(m, systemImage: "xmark.octagon").foregroundStyle(.red)
                    }
                }
            }
            .padding(20)
            Divider()
            if let r = model.result, !r.groups.isEmpty {
                List(r.groups) { group in
                    Section {
                        ForEach(group.files) { file in
                            HStack {
                                Toggle("Select \(file.name)", isOn: Binding(
                                    get: { runner.selection.contains(file.id) },
                                    set: { if $0 { runner.selection.insert(file.id) } else { runner.selection.remove(file.id) } }
                                )).labelsHidden()
                                VStack(alignment: .leading) {
                                    Text(file.name).lineLimit(1)
                                    Text(file.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.head)
                                }
                                Spacer()
                                Text(file.modified.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(group.files.count) copies · \(SizeFormat.string(group.fileSize)) each · \(SizeFormat.string(group.wastedBytes)) reclaimable")
                            Spacer()
                            Button("Keep oldest, select the rest") { model.keepOldest(in: group) }.font(.caption)
                        }
                    }
                }
                Divider()
                footer
            } else if model.result != nil, !model.scanning {
                ContentUnavailableView("No duplicates found", systemImage: "checkmark.seal",
                                       description: Text("No identical files of at least \(model.minimumMB) MB were found in this folder."))
            } else if !model.scanning {
                ContentUnavailableView {
                    Label("Find duplicate files", systemImage: "doc.on.doc.fill")
                } description: {
                    Text("Orbit compares file contents, never just names or dates. Nothing is selected for you, and one copy in each group always stays.")
                } actions: { Button("Choose a Folder…") { model.choose() }.buttonStyle(.borderedProminent).tint(.teal) }
            } else { Spacer() }
        }
        .sheet(isPresented: $runner.showingReview) {
            FileReviewSheet(runner: runner, files: model.selectedFiles, scope: model.scope ?? URL(fileURLWithPath: "/"),
                            onGone: { model.removeGone($0) })
        }
        .sheet(item: $runner.report) { FileReportSheet(report: $0) }
        .folderDrop { model.use($0) }
    }

    private var controls: some View {
        HStack {
            Picker("Minimum size", selection: Bindable(model).minimumMB) {
                Text("1 MB+").tag(1); Text("10 MB+").tag(10); Text("100 MB+").tag(100)
            }.frame(maxWidth: 140).disabled(model.scanning)
            Button("Choose Folder…") { model.choose() }.disabled(model.scanning)
            if model.scanning {
                Button("Cancel", role: .cancel) { model.cancel() }
            } else {
                Button("Scan", systemImage: "arrow.clockwise") { model.scan() }.buttonStyle(.borderedProminent).tint(.teal)
                    .disabled(model.scope == nil)
            }
        }
    }

    private var footer: some View {
        let blocked = model.fullySelectedGroups.count
        return HStack {
            if blocked > 0 {
                Label("\(blocked) group(s) have every copy selected. Deselect at least one copy in each to continue.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.caption)
            } else {
                Text(model.scope?.path ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text("\(model.runner.selection.count) selected · \(SizeFormat.string(model.selectedBytes))")
            Button("Deselect All") { model.runner.selection = [] }.disabled(model.runner.selection.isEmpty)
            Button("Review…") { model.runner.showingReview = true }
                .buttonStyle(.borderedProminent).disabled(model.runner.selection.isEmpty || blocked > 0)
        }
        .padding(12)
    }
}
