//
//  DeveloperCleanupView.swift
//  Orbit
//

import Charts
import SwiftUI

extension DevGroup {
    var tint: Color {
        switch self {
        case .buildTools: .orange
        case .agents: .cyan
        case .xcode: .blue
        case .brew: .mint
        case .node: .red
        case .docker: .indigo
        case .projects: .green
        case .deep: .brown
        case .systemJunk: .purple
        case .userCache: .blue
        case .mailFiles: .orange
        case .leftovers: .red
        }
    }
}

struct DeveloperCleanupView: View {
    /// `nil` shows every category.
    var group: DevGroup?
    @Environment(DevCleanupModel.self) private var dev
    @Environment(AppModel.self) private var model
    @State private var confirmEmptyTrash = false
    @State private var collapsed = Set<DevGroup>()

    private func matches(_ item: DevItem) -> Bool { group.map { item.group == $0 } ?? item.group.isDeveloper }
    private var scanGroups: Set<DevGroup> { group.map { [$0] } ?? Set(DevGroup.developerGroups) }
    private var showsDeepToggle: Bool { group == nil || group == .deep }

    var body: some View {
        @Bindable var dev = dev
        VStack(spacing: 0) {
            header.padding(20)
            Divider()
            if dev.result != nil { summary; toolbar; trashBar; Divider() }
            content
            if dev.result != nil { Divider(); footer }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: group?.shortName ?? "Developer Cleanup Overview",
                       subtitle: group?.subtitle ?? "Caches and build artifacts from dev tools and coding agents",
                       symbol: group?.symbol ?? "hammer.fill", trailing: AnyView(controls))
            if dev.phase == .scanning {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    ScanActivityBanner(title: "Scanning · \(Int(Date().timeIntervalSince(dev.startedAt)))s · found",
                                       detail: dev.progress.current, count: dev.progress.itemsFound)
                }
            }
            if let message = dev.accessMessage { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            if let result = dev.result, dev.phase != .scanning {
                switch result.status {
                case .completed:
                    Label("Scanned \(result.finishedAt.formatted(.relative(presentation: .named))). Sizes are on-disk estimates and nothing has been changed.\(result.skippedCount > 0 ? " \(result.skippedCount) item(s) couldn't be read." : "")",
                          systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                case .cancelled:
                    Label("Scan cancelled. Results are partial.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                case .failed(let message):
                    Label(message, systemImage: "xmark.octagon").foregroundStyle(.red)
                }
            }
        }
    }

    private var summary: some View {
        let scoped = dev.items.filter(matches)
        let safe = scoped.filter { $0.risk == .regenerable && $0.selectable }.reduce(0) { $0 + $1.bytes }
        let review = scoped.filter { $0.risk == .caution && $0.selectable }.reduce(0) { $0 + $1.bytes }
        let reportOnly = scoped.filter { !$0.selectable }.reduce(0) { $0 + $1.bytes }
        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "Found", value: SizeFormat.string(scoped.reduce(0) { $0 + $1.bytes }), caption: reportOnly > 0 ? "\(scoped.count) items · \(SizeFormat.string(reportOnly)) report-only" : "\(scoped.count) items", symbol: "tray.full.fill", tint: .teal)
                StatTile(title: "Safe to regenerate", value: SizeFormat.string(safe), caption: "Rebuilt by the tool", symbol: "arrow.triangle.2.circlepath", tint: .green)
                StatTile(title: "Review carefully", value: SizeFormat.string(review), caption: "May hold data you can't recreate", symbol: "exclamationmark.triangle.fill", tint: .orange)
            }
            if group == nil, dev.phase != .scanning {
                let rows = DevGroup.developerGroups.map { ($0, dev.bytes(in: $0)) }.filter { $0.1 > 0 }
                if !rows.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("By category").font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("Click a row to open it").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.bottom, 4)
                            let largest = Double(rows.map(\.1).max() ?? 1)
                            ForEach(rows, id: \.0) { g, bytes in
                                CategoryBarRow(group: g, bytes: bytes, fraction: Double(bytes) / largest) {
                                    Motion.run { model.section = .group(g) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var toolbar: some View {
        @Bindable var dev = dev
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search tool, name or path", text: $dev.searchText).textFieldStyle(.plain)
                if !dev.searchText.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { dev.searchText = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 280)
            Picker("Age", selection: $dev.minimumAgeDays) {
                Text("Any age").tag(0)
                Text("Untouched 30+ days").tag(30)
                Text("Untouched 90+ days").tag(90)
                Text("Untouched 180+ days").tag(180)
            }.labelsHidden().fixedSize()
            Picker("Sort", selection: $dev.sort) { ForEach(DevSort.allCases) { Text("Sort: \($0.rawValue)").tag($0) } }
                .labelsHidden().fixedSize()
            Spacer()
            Button("Select All Regenerable", systemImage: "checkmark.circle") { Motion.run { dev.selectVisibleRegenerable() } }
                .help("Selects visible items marked Regenerable. You still review before anything moves.")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var trashBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash").foregroundStyle(dev.trashReadable ? Color.secondary : Color.orange).accessibilityHidden(true)
            if let trash = dev.trash {
                Text("Trash: \(trash.itemCount) item(s), \(SizeFormat.string(trash.bytes))")
            } else if !dev.trashReadable {
                Text("Orbit can't read your Trash.")
                Button("Allow in Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)
            }
            Spacer()
            if let summary = dev.emptyTrashSummary { Text(summary).font(.caption).foregroundStyle(.secondary) }
            Button("Empty Trash…", role: .destructive) { confirmEmptyTrash = true }
                .controlSize(.small)
                .disabled((dev.trash?.itemCount ?? 0) == 0 || dev.isCleaning)
                .confirmationDialog("Permanently empty the Trash?", isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
                    Button("Empty Trash Permanently", role: .destructive) { dev.emptyTrash() }
                } message: {
                    Text("This permanently deletes everything in your Trash, including items not moved by Orbit. It can't be undone.")
                }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background((dev.trashReadable ? Color.secondary : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    private var controls: some View {
        @Bindable var dev = dev
        return HStack {
            if showsDeepToggle {
                Toggle("Deep cleanup", isOn: $dev.deepScan)
                    .toggleStyle(.switch).disabled(dev.phase == .scanning)
                    .help("Also scans ~/.cache, stale installers in Downloads, and Python/.NET build junk. Slower. Items Orbit can't verify are marked Review carefully.")
            }
            if dev.phase == .scanning {
                Button("Cancel Scan", role: .cancel) { dev.cancel() }
            } else {
                Button(dev.result == nil ? "Scan" : "Scan Again", systemImage: "arrow.clockwise") { dev.grantAccessAndScan(groups: scanGroups) }
                    .buttonStyle(.borderedProminent).tint(.teal)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let result = dev.result, case .failed = result.status {
            ContentUnavailableView("Couldn't scan", systemImage: "lock.slash",
                                   description: Text("Grant access to your home folder and try again."))
        } else if dev.result == nil || (group != nil && dev.items(in: group!).isEmpty && !dev.hasScanned(group!)) {
            if dev.phase == .scanning { Spacer() } else {
                ContentUnavailableView {
                    Label(group.map { "Scan \($0.shortName)" } ?? "Find developer clutter", systemImage: group?.symbol ?? "hammer.fill")
                } description: {
                    Text(group.map { $0.subtitle + ". You review everything before it moves to the Trash." } ?? "Orbit checks Gradle, Maven, npm, Xcode, Cursor, Claude, Antigravity and more, plus node_modules and build folders in your projects. You review everything before it moves to the Trash.")
                } actions: {
                    Button("Grant Access & Scan") { dev.grantAccessAndScan(groups: scanGroups) }.buttonStyle(.borderedProminent).tint(.teal)
                }
            }
        } else if dev.visibleItems.filter(matches).isEmpty {
            ContentUnavailableView(dev.items.isEmpty || group != nil ? (dev.result?.status.isPartial == true ? "Nothing found yet" : "Nothing in this category") : "No matches",
                                   systemImage: "checkmark.seal",
                                   description: Text(group == .deep && !dev.deepScan ? "Turn on Deep cleanup and scan again to populate this category." : dev.items.isEmpty ? "No known developer caches or build folders were found." : "Nothing here matches the current scan and filters."))
        } else {
            List {
                ForEach(group.map { [$0] } ?? DevGroup.developerGroups) { g in
                    let rows = dev.visibleItems.filter { $0.group == g }
                    if !rows.isEmpty {
                        DisclosureGroup(isExpanded: Binding(
                            get: { !collapsed.contains(g) },
                            set: { open in Motion.run { if open { collapsed.remove(g) } else { collapsed.insert(g) } } }
                        )) {
                            ForEach(rows) { DevRow(item: $0).transition(.opacity.combined(with: .move(edge: .leading))) }
                        } label: {
                            HStack {
                                Label(g.rawValue, systemImage: g.symbol).font(.headline).foregroundStyle(g.tint)
                                Text("\(rows.count)").font(.caption).foregroundStyle(.secondary)
                                    .padding(.horizontal, 6).background(.quaternary, in: Capsule())
                                Spacer()
                                if rows.contains(where: { $0.risk == .regenerable && $0.selectable }) {
                                    Button("Select Safe") {
                                        Motion.run { dev.selection.formUnion(rows.filter { $0.risk == .regenerable && $0.selectable }.map(\.id)) }
                                    }
                                    .buttonStyle(.borderless).font(.caption)
                                }
                                Text(SizeFormat.string(rows.reduce(0) { $0 + $1.bytes })).foregroundStyle(.secondary).numeric(rows.count)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if !dev.selection.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(dev.selection.count) selected · \(SizeFormat.string(dev.selectedBytes))").font(.headline).numeric(dev.selectedBytes)
                        let hidden = dev.selection.count - dev.visibleItems.filter { dev.selection.contains($0.id) }.count
                        if hidden > 0 { Text("\(hidden) selected item(s) are hidden by filters").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Deselect All") { Motion.run { dev.selection = [] } }
                    Button("Review…") { dev.showingReview = true }
                        .buttonStyle(.borderedProminent).tint(.teal).keyboardShortcut(.return, modifiers: .command)
                }
                .padding(12)
                .background(.teal.opacity(0.10))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Nothing is selected by default. Moving to the Trash frees space once you empty the Trash.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .animation(Motion.spring, value: dev.selection.isEmpty)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let caption: String
    let symbol: String
    let tint: Color

    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 34, height: 34)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.title3.weight(.bold)).monospacedDigit().numeric(value)
                    Text(caption).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct DevRow: View {
    @Environment(DevCleanupModel.self) private var dev
    let item: DevItem

    private var staleDays: Int? {
        guard item.modified > .distantPast else { return nil }
        let days = Calendar.current.dateComponents([.day], from: item.modified, to: Date()).day ?? 0
        return days >= 90 ? days : nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Select \(item.title)", isOn: Binding(
                get: { dev.selection.contains(item.id) }, set: { on in Motion.run { dev.setSelected(item, on) } }
            )).labelsHidden().disabled(!item.selectable).padding(.top, 6)
            Image(systemName: item.group.symbol).foregroundStyle(item.group.tint)
                .frame(width: 34, height: 34)
                .background(item.group.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.headline)
                    Text(item.tool).font(.caption).foregroundStyle(.secondary)
                    RiskBadge(risk: item.risk)
                    if !item.selectable { Label("Report only", systemImage: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                    if let days = staleDays {
                        Label("Untouched \(days >= 365 ? "\(days / 365)y" : "\(days)d")", systemImage: "clock")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(item.reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(item.url.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(SizeFormat.string(item.bytes)).font(.body.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 6)
        .opacity(item.selectable ? 1 : 0.75)
        .contextMenu { Button("Show in Finder") { dev.reveal(item) } }
    }
}

struct RiskBadge: View {
    let risk: DevRisk
    var body: some View {
        Label(risk.rawValue, systemImage: risk == .regenerable ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
            .font(.caption2.weight(.medium))
            .foregroundStyle(risk == .regenerable ? Color.green : Color.orange)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((risk == .regenerable ? Color.green : Color.orange).opacity(0.12), in: Capsule())
    }
}

struct DevReviewSheet: View {
    @Environment(DevCleanupModel.self) private var dev

    var body: some View {
        let items = dev.selectedItems
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Cleanup").font(.title2.bold())
            Text("\(items.count) folder(s), about \(SizeFormat.string(dev.selectedBytes)), will be moved to the Trash. Nothing is permanently deleted, and you can put items back. Space is freed after you empty the Trash. Folders that changed since the scan are skipped. Quit related apps first.")
                .fixedSize(horizontal: false, vertical: true)
            if items.contains(where: { $0.risk == .caution }) {
                Label("Includes items marked “Review carefully” that may hold data that can't be recreated.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            List(items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        HStack { Text(item.title); RiskBadge(risk: item.risk) }
                        Text(item.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(SizeFormat.string(item.bytes))
                    Button("Remove from selection", systemImage: "minus.circle") { dev.setSelected(item, false) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 240)
            HStack {
                Button("Cancel", role: .cancel) { dev.showingReview = false }.keyboardShortcut(.cancelAction).disabled(dev.isCleaning)
                Spacer()
                if let p = dev.cleanProgress {
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).frame(width: 140)
                    Text("\(p.done) of \(p.total)\(p.current.isEmpty ? "" : ": \(p.current)")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 220, alignment: .leading)
                    Button("Stop") { dev.cancelCleanup() }
                }
                Button("Move \(items.count) to Trash", role: .destructive) { dev.executeCleanup() }
                    .buttonStyle(.borderedProminent).disabled(items.isEmpty || dev.isCleaning)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 460)
        .onChange(of: items.isEmpty) { _, empty in if empty { dev.showingReview = false } }
    }
}

struct DevReportSheet: View {
    @Environment(DevCleanupModel.self) private var dev
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let report = dev.report {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cleanup Results").font(.title2.bold())
                Label("\(report.completed.count) moved to Trash (about \(SizeFormat.string(report.estimatedMovedBytes)); space is freed when you empty the Trash)",
                      systemImage: "checkmark.circle")
                Label("\(report.notCompleted.count) skipped or failed", systemImage: "arrow.uturn.right.circle")
                List(report.notCompleted) { r in
                    VStack(alignment: .leading) {
                        Text(r.item.title)
                        Text(describe(r.outcome)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 120)
                HStack {
                    if report.completed.contains(where: { $0.trashedURL != nil }) {
                        Button("Put Back All", systemImage: "arrow.uturn.backward") { dev.putBack(report); dismiss() }
                    }
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20).frame(minWidth: 520, minHeight: 340)
        }
    }

    private func describe(_ outcome: CleanupOutcome) -> String {
        switch outcome {
        case .completed: "Moved to Trash"
        case .skipped(let why): "Skipped: \(why)"
        case .failed(let why): "Failed: \(why)"
        }
    }
}

extension DevCleanupReport: Identifiable {
    var id: Int { results.count &+ (results.first?.id.hashValue ?? 0) }
}

/// One clickable row of the category overview: icon and name, a proportional bar, and the size.
private struct CategoryBarRow: View {
    let group: DevGroup
    let bytes: Int64
    let fraction: Double
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Label(group.shortName, systemImage: group.symbol)
                    .font(.callout).foregroundStyle(.primary)
                    .frame(width: 190, alignment: .leading).lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary.opacity(0.5))
                        Capsule().fill(group.tint.gradient).frame(width: max(6, geo.size.width * fraction))
                    }
                }
                .frame(height: 10)
                Text(SizeFormat.string(bytes)).font(.callout.weight(.medium)).monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.spring, value: hovering)
    }
}
