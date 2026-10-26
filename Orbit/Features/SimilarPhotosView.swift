//
//  SimilarPhotosView.swift
//  Orbit
//

import SwiftUI

@Observable
final class SimilarPhotosModel {
    enum Strictness: Float, CaseIterable, Identifiable {
        case veryClose = 0.25, close = 0.45, loose = 0.65
        var id: Float { rawValue }
        var label: String { switch self { case .veryClose: "Very close"; case .close: "Close"; case .loose: "Loose" } }
    }

    private(set) var scope: URL?
    private(set) var result: PhotoResult?
    private(set) var scanning = false
    private(set) var progress = (done: 0, total: 0)
    var strictness = Strictness.close
    let runner = FileCleanupRunner()
    private var task: Task<Void, Never>?

    func choose() {
        guard !scanning, let url = FolderPicker.choose(message: "Choose a folder of photos to compare.") else { return }
        scope = url; result = nil; runner.selection = []
    }

    func use(_ url: URL) {
        guard !scanning else { return }
        scope = url; result = nil; runner.selection = []
    }

    func scan() {
        guard let scope, !scanning else { return }
        scanning = true
        progress = (0, 0)
        runner.selection = []
        let distance = strictness.rawValue
        task = Task {
            let found = await PhotoSimilarityFinder().find(root: scope, maxDistance: distance) { done, total in
                Task { @MainActor in self.progress = (done, total) }
            }
            Motion.run { result = found; scanning = false }
        }
    }

    func cancel() { task?.cancel() }

    var selectedFiles: [ScannedFile] { (result?.groups.flatMap(\.files) ?? []).filter { runner.selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.allocatedSize } }
    var fullySelectedGroups: Int {
        (result?.groups ?? []).filter { g in g.files.allSatisfy { runner.selection.contains($0.id) } }.count
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

struct SimilarPhotosView: View {
    @Environment(SimilarPhotosModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var runner = model.runner
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "Similar Photos", subtitle: "Visually similar images, compared on your Mac",
                           symbol: "photo.stack.fill", trailing: AnyView(controls))
                if model.scanning {
                    ScanActivityBanner(title: "Analyzing photos", detail: "\(model.progress.done) of \(model.progress.total)", count: model.progress.done)
                }
                if let r = model.result, !model.scanning {
                    switch r.status {
                    case .completed:
                        Label("Checked \(r.photosExamined.formatted()) photos\(r.truncated ? " (limited to the first \(r.photosExamined.formatted()))" : ""). Matches are suggestions: look before you select.",
                              systemImage: "checkmark.circle")
                    case .cancelled: Label("Scan cancelled. Results are partial.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    case .failed(let m): Label(m, systemImage: "xmark.octagon").foregroundStyle(.red)
                    }
                }
            }
            .padding(20)
            Divider()
            if let r = model.result, !r.groups.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(r.groups) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(group.files.count) similar photos").font(.headline)
                                ScrollView(.horizontal) {
                                    HStack(alignment: .top, spacing: 12) {
                                        ForEach(group.files) { file in
                                            VStack(alignment: .leading, spacing: 4) {
                                                ThumbnailView(url: file.url)
                                                Toggle(file.name, isOn: Binding(
                                                    get: { runner.selection.contains(file.id) },
                                                    set: { if $0 { runner.selection.insert(file.id) } else { runner.selection.remove(file.id) } }
                                                )).font(.caption).lineLimit(1).frame(width: 120, alignment: .leading)
                                                Text(SizeFormat.string(file.allocatedSize)).font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                Divider()
                footer
            } else if model.result != nil, !model.scanning {
                ContentUnavailableView("No similar photos found", systemImage: "checkmark.seal",
                                       description: Text("Try a looser similarity setting or a different folder."))
            } else if !model.scanning {
                ContentUnavailableView {
                    Label("Find similar photos", systemImage: "photo.stack.fill")
                } description: {
                    Text("Orbit uses Apple's on-device Vision analysis. No photos leave your Mac, and nothing is selected for you.")
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
            Picker("Similarity", selection: Bindable(model).strictness) {
                ForEach(SimilarPhotosModel.Strictness.allCases) { Text($0.label).tag($0) }
            }.frame(maxWidth: 200).disabled(model.scanning)
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
        let blocked = model.fullySelectedGroups
        return HStack {
            if blocked > 0 {
                Label("\(blocked) group(s) have every photo selected. Keep at least one in each.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.caption)
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
