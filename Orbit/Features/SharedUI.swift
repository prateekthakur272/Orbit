//
//  SharedUI.swift
//  Orbit
//

import AppKit
import SwiftUI

enum FolderPicker {
    /// Shows the native folder picker. Returns the folder with security-scoped access started.
    static func choose(message: String, start: URL? = nil, showHidden: Bool = false) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
        panel.showsHiddenFiles = showHidden
        panel.prompt = "Choose"
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}

/// Shared state for features that move reviewed files to the Trash (duplicates, similar photos).
@Observable
final class FileCleanupRunner {
    var selection = Set<String>()
    var showingReview = false
    private(set) var isCleaning = false
    var report: CleanupReport?

    func run(files: [ScannedFile], scope: URL, onGone: @escaping (Set<String>) -> Void) {
        guard !isCleaning, !files.isEmpty else { return }
        isCleaning = true
        Task {
            let outcome = await CleanupExecutor().execute(files: files, scope: scope)
            let gone = Set(outcome.results.filter {
                if case .completed = $0.outcome { return true }
                if case .skipped(let why) = $0.outcome, why.hasPrefix("No longer exists") { return true }
                return false
            }.map(\.id))
            Motion.run { selection.subtract(gone); onGone(gone) }
            report = outcome
            ToastCenter.shared.show("Moved \(outcome.completed.count) file(s) to the Trash")
            showingReview = false
            isCleaning = false
        }
    }
}

struct FileReviewSheet: View {
    var runner: FileCleanupRunner
    let files: [ScannedFile]
    let scope: URL
    var onGone: (Set<String>) -> Void

    var body: some View {
        let bytes = files.reduce(0) { $0 + $1.allocatedSize }
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Cleanup").font(.title2.bold())
            Text("\(files.count) file(s) · about \(SizeFormat.string(bytes)) will be moved to the Trash. Nothing is permanently deleted. Files that moved or changed since the scan will be skipped.")
                .fixedSize(horizontal: false, vertical: true)
            List(files) { file in
                HStack {
                    VStack(alignment: .leading) {
                        Text(file.name).lineLimit(1)
                        Text(file.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(SizeFormat.string(file.allocatedSize))
                    Button("Remove from selection", systemImage: "minus.circle") { runner.selection.remove(file.id) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 240)
            HStack {
                Button("Cancel", role: .cancel) { runner.showingReview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                if runner.isCleaning { ProgressView().controlSize(.small) }
                Button("Move \(files.count) to Trash", role: .destructive) { runner.run(files: files, scope: scope, onGone: onGone) }
                    .buttonStyle(.borderedProminent).disabled(files.isEmpty || runner.isCleaning)
            }
        }
        .padding(20).frame(minWidth: 620, minHeight: 440)
        .onChange(of: files.isEmpty) { _, empty in if empty { runner.showingReview = false } }
    }
}

struct FileReportSheet: View {
    let report: CleanupReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Results").font(.title2.bold())
            Label("\(report.completed.count) moved to Trash (about \(SizeFormat.string(report.estimatedMovedBytes)), an estimate; space is freed when you empty the Trash)", systemImage: "checkmark.circle")
            Label("\(report.skipped.count) skipped, \(report.failed.count) failed", systemImage: "arrow.uturn.right.circle")
            List(report.results.filter { $0.outcome != .completed }) { item in
                VStack(alignment: .leading) {
                    Text(item.file.name)
                    Text(describe(item.outcome)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 120)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(minWidth: 520, minHeight: 340)
    }

    private func describe(_ outcome: CleanupOutcome) -> String {
        switch outcome {
        case .completed: "Moved to Trash"
        case .skipped(let why): "Skipped: \(why)"
        case .failed(let why): "Failed: \(why)"
        }
    }
}

struct DevReportContent: View {
    let report: DevCleanupReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results").font(.title2.bold())
            Label("\(report.completed.count) moved to Trash (about \(SizeFormat.string(report.estimatedMovedBytes)); space is freed when you empty the Trash)", systemImage: "checkmark.circle")
            Label("\(report.notCompleted.count) skipped or failed", systemImage: "arrow.uturn.right.circle")
            List(report.notCompleted) { r in
                VStack(alignment: .leading) {
                    Text(r.item.title)
                    Text(String(describing: r.outcome).replacingOccurrences(of: "skipped(\"", with: "Skipped: ").replacingOccurrences(of: "failed(\"", with: "Failed: ").replacingOccurrences(of: "\")", with: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 120)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(minWidth: 520, minHeight: 340)
    }
}

/// Lazily loads a downsampled thumbnail so lists of photos stay light.
struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() } else { Rectangle().fill(.quaternary) }
        }
        .frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) {
            let url = url
            image = await Task.detached(priority: .utility) {
                PhotoSimilarityFinder.thumbnail(url: url, maxPixel: 240).map { NSImage(cgImage: $0, size: .zero) }
            }.value
        }
        .accessibilityHidden(true)
    }
}

/// Drop-in replacement for `ContentUnavailableView` that fills the space below a page header,
/// so empty states center in the remaining area instead of shrinking the whole page.
struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    private let inner: SwiftUI.ContentUnavailableView<Label, Description, Actions>

    init(@ViewBuilder label: () -> Label, @ViewBuilder description: () -> Description = { EmptyView() },
         @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        inner = SwiftUI.ContentUnavailableView(label: label, description: description, actions: actions)
    }

    var body: some View { inner.frame(maxWidth: .infinity, maxHeight: .infinity) }
}

extension ContentUnavailableView where Label == SwiftUI.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    init<S: StringProtocol>(_ title: S, systemImage name: String, description: Text? = nil) {
        self.init(label: { SwiftUI.Label(String(title), systemImage: name) }, description: { description })
    }
}

// MARK: - Motion & interaction

enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var spring: Animation? { reduce ? nil : .spring(duration: 0.35, bounce: 0.15) }
    /// Runs `body` inside an animation unless the user turned on Reduce Motion.
    static func run(_ body: () -> Void) {
        if reduce { body() } else { withAnimation(spring, body) }
    }
}

/// Lightweight confirmation messages ("Moved 12 items to the Trash").
@Observable
final class ToastCenter {
    static let shared = ToastCenter()
    private(set) var message: String?
    private(set) var symbol = "checkmark.circle.fill"
    private var task: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        task?.cancel()
        Motion.run { self.message = message; self.symbol = symbol }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        task = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            Motion.run { self.message = nil }
        }
    }

    func dismiss() { task?.cancel(); Motion.run { message = nil } }
}

struct ToastOverlay: ViewModifier {
    var toasts = ToastCenter.shared

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = toasts.message {
                Button { toasts.dismiss() } label: {
                    Label(message, systemImage: toasts.symbol)
                        .symbolEffect(.bounce, value: message)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.quaternary))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

struct HoverLift: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !Motion.reduce ? 1.015 : 1)
            .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: 10, y: 5)
            .animation(Motion.spring, value: hovering)
            .onHover { hovering = $0 }
    }
}

struct FolderDrop: ViewModifier {
    var onDrop: (URL) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) else { return false }
                _ = url.startAccessingSecurityScopedResource()
                onDrop(url)
                return true
            } isTargeted: { targeted = $0 }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.teal, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(Label("Drop a folder to use it", systemImage: "folder.badge.plus").font(.title3.weight(.semibold)).foregroundStyle(.teal))
                        .padding(8).allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(Motion.spring, value: targeted)
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
    func folderDrop(_ onDrop: @escaping (URL) -> Void) -> some View { modifier(FolderDrop(onDrop: onDrop)) }
    func toastHost() -> some View { modifier(ToastOverlay()) }
    /// Animated digit changes for sizes and counts.
    func numeric<V: Equatable>(_ value: V) -> some View {
        contentTransition(.numericText()).animation(Motion.spring, value: value)
    }
}

/// Live status shown while a scan runs: a pulsing icon, a counter and an indeterminate bar.
struct ScanActivityBanner: View {
    let title: String
    let detail: String
    var count: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3).foregroundStyle(.teal)
                .symbolEffect(.variableColor.iterative.reversing, isActive: !Motion.reduce)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.callout.weight(.semibold))
                    if let count { Text("\(count.formatted())").font(.callout.monospacedDigit()).foregroundStyle(.secondary).numeric(count) }
                }
                ProgressView().progressViewStyle(.linear).tint(.teal)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(12)
        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
