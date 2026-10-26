//
//  ContentView.swift
//  Orbit
//
//  Created by ENT-0554 on 26/10/26.
//

import Charts
import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var onboarded = false

    var body: some View {
        if onboarded {
            MainView()
        } else {
            OnboardingView { onboarded = true }
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    var finish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.system(size: 54)).foregroundStyle(.tint).accessibilityHidden(true)
            Text("Welcome to Orbit").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 10) {
                Label("Orbit shows what's using space in a folder you choose and lists its largest files.", systemImage: "folder")
                Label("macOS only lets Orbit read folders you pick. It never tries to get around that.", systemImage: "lock.shield")
                Label("Scanning never deletes anything. Cleanup always shows a review first, and moves files to the Trash.", systemImage: "trash")
                Label("Everything stays on your Mac. Nothing is uploaded.", systemImage: "network.slash")
            }
            .frame(maxWidth: 480, alignment: .leading)
            HStack(spacing: 12) {
                Button("Allow Full Disk Access…") { model.openFullDiskAccessSettings() }
                    .controlSize(.large)
                Button("Get Started") {
                    finish()
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text("Full Disk Access is optional but gives more complete results. You can also allow it later. Orbit asks for your home folder the first time you scan.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(DevCleanupModel.self) private var dev
    @Environment(AppsModel.self) private var apps
    @Environment(\.openSettings) private var openSettings

    /// Only categories the last scan actually found something in.
    private var cleanupGroups: [DevGroup] { DevGroup.allCases.filter { !$0.isDeveloper && !dev.items(in: $0).isEmpty } }
    private var developerFoundGroups: [DevGroup] { DevGroup.developerGroups.filter { !dev.items(in: $0).isEmpty } }

    private func badge(_ group: DevGroup) -> String? {
        dev.result == nil || !dev.hasScanned(group) ? nil : SizeFormat.string(dev.bytes(in: group))
    }

    var body: some View {
        @Bindable var model = model
        @Bindable var dev = dev
        NavigationSplitView {
            List(selection: Binding(get: { Optional(model.section) }, set: { if let v = $0 { model.section = v } })) {
                SwiftUI.Section {
                    SidebarRow(title: "Smart Care", symbol: "sparkles", tint: .teal).tag(AppModel.Section.smartCare)
                }
                if dev.result != nil {
                    if !cleanupGroups.isEmpty {
                        SwiftUI.Section("Cleanup") {
                            ForEach(cleanupGroups) { group in
                                SidebarRow(title: group.shortName, symbol: group.symbol, tint: group.tint, badge: badge(group))
                                    .tag(AppModel.Section.group(group))
                            }
                        }
                    }
                    if !developerFoundGroups.isEmpty {
                        SwiftUI.Section("Developer Cleanup") {
                            ForEach(developerFoundGroups) { group in
                                SidebarRow(title: group.shortName, symbol: group.symbol, tint: group.tint, badge: badge(group))
                                    .tag(AppModel.Section.group(group))
                            }
                        }
                    }
                }
                SwiftUI.Section("Tools") {
                    SidebarRow(title: "Space Explorer", symbol: "chart.pie.fill", tint: .teal).tag(AppModel.Section.spaceExplorer)
                    SidebarRow(title: "Large & Old Files", symbol: "doc.fill", tint: .yellow).tag(AppModel.Section.largeFiles)
                    SidebarRow(title: "Duplicate Finder", symbol: "doc.on.doc.fill", tint: .indigo).tag(AppModel.Section.duplicates)
                    SidebarRow(title: "Similar Photos", symbol: "photo.stack.fill", tint: .pink).tag(AppModel.Section.similarPhotos)
                    SidebarRow(title: "Uninstaller", symbol: "app.dashed", tint: .blue, badge: apps.loaded ? "\(apps.apps.count)" : nil)
                        .tag(AppModel.Section.uninstaller)
                    SidebarRow(title: "App Updates", symbol: "arrow.triangle.2.circlepath", tint: .teal).tag(AppModel.Section.appUpdates)
                    SidebarRow(title: "Trash Bins", symbol: "trash.fill", tint: .red,
                               badge: dev.trash.map { SizeFormat.string($0.bytes) }).tag(AppModel.Section.trashBins)
                    SidebarRow(title: "Protection", symbol: "shield.fill", tint: .green).tag(AppModel.Section.protection)
                    SidebarRow(title: "Performance", symbol: "gauge.with.dots.needle.67percent", tint: .cyan).tag(AppModel.Section.performance)
                }
                SwiftUI.Section {
                    SidebarRow(title: "History", symbol: "clock.arrow.circlepath", tint: .mint).tag(AppModel.Section.history)
                    SidebarRow(title: "Settings", symbol: "gearshape.fill", tint: .gray).tag(AppModel.Section.settings)
                }
            }
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            Group {
            switch model.section {
            case .smartCare: SmartCareView()
            case .protection: ProtectionView()
            case .performance: PerformanceView()
            case .uninstaller: UninstallerView()
            case .appUpdates: AppUpdatesView()
            case .spaceExplorer: SpaceExplorerView()
            case .duplicates: DuplicatesView()
            case .similarPhotos: SimilarPhotosView()
            case .group(let group): DeveloperCleanupView(group: group).id(group)
            case .trashBins: TrashBinsView()
            case .largeFiles: LargeFilesPage()
            case .history: HistoryView()
            case .settings: EmptyView()   // opens the Settings window instead
            }
            }
            .id(model.section)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 18)), removal: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Motion.spring, value: model.section)
        }
        .onChange(of: model.section) { old, new in
            // Settings lives in its own window (also ⌘,), so don't leave it selected in the sidebar.
            guard new == .settings else { return }
            model.section = old == .settings ? .smartCare : old
            openSettings()
        }
        .sheet(isPresented: $model.showingReview) { ReviewSheet() }
        .sheet(item: $model.report) { _ in ReportSheet() }
        .sheet(isPresented: $dev.showingReview) { DevReviewSheet() }
        .sheet(item: $dev.report) { _ in DevReportSheet() }
    }
}

extension CleanupReport: Identifiable {
    var id: Int { results.count &+ (results.first?.id.hashValue ?? 0) }
}

struct SidebarFooter: View {
    @Environment(DevCleanupModel.self) private var dev
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(dev.home != nil ? Color.green : Color.orange).frame(width: 8, height: 8).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(dev.home != nil ? "Home folder access" : "No folder access yet").font(.subheadline.weight(.semibold))
                    Text(dev.home != nil ? "Granted for this session" : "Orbit asks when a scan needs it")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
        .padding(12)
        .background(.bar)
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let tint: Color
    var badge: String?

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let badge {
                    Text(badge).font(.caption2.weight(.medium)).foregroundStyle(.secondary).numeric(badge)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(.quaternary, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.teal)
                .frame(width: 48, height: 48)
                .background(.teal.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }
}

// MARK: - Smart Care

enum ScanStrategy: String, CaseIterable, Identifiable {
    case quick, developer, everything, deep
    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: "Quick Scan"
        case .developer: "Developer Scan"
        case .everything: "Full Scan"
        case .deep: "Deep Scan"
        }
    }

    var detail: String {
        switch self {
        case .quick: "System junk, app caches and mail downloads. Fastest."
        case .developer: "Xcode, Gradle, npm, Docker, AI tools and project build folders."
        case .everything: "Everything above plus app leftovers."
        case .deep: "Full scan plus ~/.cache, stale installers and Python/.NET build junk. Slowest."
        }
    }

    var symbol: String {
        switch self {
        case .quick: "bolt.fill"
        case .developer: "hammer.fill"
        case .everything: "sparkle.magnifyingglass"
        case .deep: "scope"
        }
    }

    var tint: Color {
        switch self {
        case .quick: .yellow
        case .developer: .purple
        case .everything: .teal
        case .deep: .indigo
        }
    }

    var groups: Set<DevGroup> {
        switch self {
        case .quick: [.systemJunk, .userCache, .mailFiles]
        case .developer: Set(DevGroup.developerGroups.filter { $0 != .deep })
        case .everything, .deep: Set(DevGroup.allCases)
        }
    }

    var isDeep: Bool { self == .deep }
}

struct SmartCareView: View {
    @Environment(AppModel.self) private var model
    @Environment(DevCleanupModel.self) private var dev
    @State private var choosingScan = false
    @State private var hasFDA = true
    @AppStorage("scanStrategy") private var strategyName = ScanStrategy.everything.rawValue

    private var strategy: ScanStrategy { ScanStrategy(rawValue: strategyName) ?? .everything }

    var body: some View {
        Group {
            if dev.phase == .scanning {
                scanningSection
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if !hasFDA { fullDiskAccessBanner }
                        StorageCard()
                        if let result = dev.result, !choosingScan {
                            resultsSection(result).transition(.opacity)
                        } else {
                            optionsSection.transition(.opacity)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { hasFDA = model.hasFullDiskAccess }
        // Re-check when the user comes back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFDA = model.hasFullDiskAccess
        }
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Allow Full Disk Access").font(.headline)
                Text("Without it, protected folders (Mail, Safari, Photos and others) are skipped and results will be incomplete. In System Settings, turn on Orbit under Full Disk Access.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open System Settings") { model.openFullDiskAccessSettings() }
                .buttonStyle(.borderedProminent).tint(.orange)
        }
        .padding(14)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Smart Care").font(.largeTitle.bold())
            Text("See your storage, choose how deep to look, then scan.").foregroundStyle(.secondary)
        }
    }

    /// Full-page, centered while a scan runs.
    private var scanningSection: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text("Smart Care").font(.largeTitle.bold())
                    Text("Scanning your Mac. This is read-only.").foregroundStyle(.secondary)
                }
                ScanOrbView(count: dev.progress.itemsFound, detail: dev.progress.current, startedAt: dev.startedAt,
                            size: max(340, min(geo.size.width - 48, (geo.size.height - 260) / 0.62, 760)))
                Button("Stop Scan") { dev.cancel() }.controlSize(.large)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .transition(.opacity)
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scan strategy").font(.title3.bold())
                ForEach(ScanStrategy.allCases) { option in
                    StrategyRow(option: option, selected: option == strategy) {
                        Motion.run { strategyName = option.rawValue }
                    }
                }
            }
            HStack(spacing: 14) {
                Button(action: scan) {
                    Label("Scan", systemImage: "magnifyingglass").font(.headline).frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent).tint(.teal).controlSize(.extraLarge)
                .keyboardShortcut("r")
                Text("Scanning is read-only. You review everything before it moves to the Trash.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func resultsSection(_ result: DevScanResult) -> some View {
        let groups = DevGroup.allCases.filter { !dev.items(in: $0).isEmpty }
        let total = dev.items.filter(\.selectable).reduce(0) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: 16) {
            Label(result.status.isPartial
                  ? "Scan stopped early. Results are partial."
                  : "Found \(SizeFormat.string(total)) in \(dev.items.count) items.",
                  systemImage: result.status.isPartial ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.headline)
                .foregroundStyle(result.status.isPartial ? .orange : .green)
            if groups.isEmpty {
                Text("Nothing to clean up.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    ForEach(groups) { group in
                        Button { Motion.run { model.section = .group(group) } } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: group.symbol).font(.title3).foregroundStyle(.teal)
                                Text(group.shortName).font(.headline)
                                Text(SizeFormat.string(dev.bytes(in: group))).font(.title2.bold()).monospacedDigit()
                                Text("\(dev.items(in: group).count) items").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.2)))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Button("Scan Again") { Motion.run { choosingScan = true } }
                Text("Last scan \(result.finishedAt.formatted(.relative(presentation: .named)))")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func scan() {
        choosingScan = false
        dev.deepScan = strategy.isDeep
        dev.grantAccessAndScan(groups: strategy.groups)
    }
}

private struct StrategyRow: View {
    let option: ScanStrategy
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 14) {
                Image(systemName: option.symbol).foregroundStyle(option.tint)
                    .frame(width: 38, height: 38)
                    .background(option.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.headline)
                    Text(option.detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? Color.teal : Color.secondary.opacity(0.5))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Color.teal.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.teal : Color.secondary.opacity(0.2), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct StatusChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            switch model.phase {
            case .scanning: Label("Scanning", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
            default:
                if let r = model.result, case .failed = r.status {
                    Label("Scan failed", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                } else if let r = model.result, r.status.isPartial {
                    Label("Partial scan", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            Text(model.result.map { "Last scan \($0.finishedAt.formatted(date: .abbreviated, time: .shortened))" } ?? "No scan run yet")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout.weight(.medium))
    }
}

struct StorageCard: View {
    @Environment(AppModel.self) private var model

    private struct Slice: Identifiable { let id: String; let bytes: Int64; let color: Color }
    /// 0...1 sweep of the ring. Plays once per launch, so switching pages or refreshing doesn't replay it.
    private static var played = false
    @State private var sweep = (Self.played || Motion.reduce) ? 1.0 : 0.0

    /// Fills the slices in order up to `sweep` of the total, so the ring draws like a clock hand instead of every slice scaling at once.
    private func visible(_ slices: [Slice], total: Int64) -> [Slice] {
        var left = Double(total) * sweep
        var out: [Slice] = []
        for s in slices {
            let shown = min(Double(s.bytes), max(0, left))
            left -= shown
            out.append(Slice(id: s.id, bytes: Int64(shown), color: s.color))
        }
        let rest = Double(total) - out.reduce(0) { $0 + Double($1.bytes) }
        if rest > 0 { out.append(Slice(id: "", bytes: Int64(rest), color: .clear)) }
        return out
    }

    var body: some View {
        let v = model.volume
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Mac storage").font(.headline)
                        Text(v.availableForImportantUsage.map { "\(SizeFormat.string($0)) available" } ?? "Available space unavailable")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh storage", systemImage: "arrow.clockwise") { model.refreshVolume() }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.teal)
                }
                if let total = v.total, let used = v.used, let purgeable = v.purgeable, let avail = v.available {
                    let slices = [
                        Slice(id: "Used", bytes: used, color: .gray),
                        Slice(id: "Purgeable", bytes: purgeable, color: .teal),
                        Slice(id: "Available", bytes: avail, color: Color(nsColor: .systemTeal).opacity(0.35)),
                    ]
                    HStack(spacing: 16) {
                        Chart(visible(slices, total: used + purgeable + avail)) { s in
                            SectorMark(angle: .value("Bytes", s.bytes), innerRadius: .ratio(0.78), angularInset: s.color == .clear ? 0 : 1)
                                .foregroundStyle(s.color)
                        }
                        .frame(width: 130, height: 130)
                        .onAppear {
                            guard sweep < 1 else { return }
                            Self.played = true
                            withAnimation(.timingCurve(0.25, 0.8, 0.25, 1, duration: 1.2)) { sweep = 1 }
                        }
                        .overlay {
                            VStack(spacing: 0) {
                                Text("\(Int((Double(used) / Double(max(total, 1)) * 100).rounded()))%").font(.title.bold())
                                Text("USED").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        VStack(spacing: 8) {
                            ForEach(slices) { s in
                                HStack {
                                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(s.color)
                                    Text(s.id).font(.callout)
                                    Spacer()
                                    Text(SizeFormat.string(s.bytes)).font(.callout.weight(.semibold))
                                }
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("Capacity information is unavailable.").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Large Files page

struct LargeFilesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(title: "Large & Old Files", subtitle: "Big or stale files in a folder you choose, or your whole Mac", symbol: "doc.fill",
                           trailing: AnyView(scanControls))
                if model.phase == .scanning {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        ScanActivityBanner(title: "Scanning · \(Int(Date().timeIntervalSince(model.scanStartedAt)))s · files examined",
                                           detail: model.progress.currentFolder.isEmpty ? (model.scope?.path ?? "") : model.progress.currentFolder,
                                           count: model.progress.filesExamined)
                    }
                }
                statusLine
                if model.isWholeMac && !model.hasFullDiskAccess {
                    HStack {
                        Label("Without Full Disk Access, protected folders (Mail, Photos, Safari and others) are skipped and the scan will be incomplete.",
                              systemImage: "lock.shield").font(.callout)
                        Spacer()
                        Button("Open Settings") { model.openFullDiskAccessSettings() }
                    }
                    .padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
            Divider()
            ResultsArea()
        }
        .folderDrop { model.use($0) }
    }

    private var scanControls: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Button("Scan Entire Mac") { model.scanEntireMac() }.disabled(model.phase == .scanning)
                Button("Choose Folder…") { model.chooseFolder() }.disabled(model.phase == .scanning)
                if model.phase == .scanning {
                    Button("Cancel Scan", role: .cancel) { model.cancelScan() }
                } else {
                    Button(model.result == nil ? "Scan" : "Scan Again", systemImage: "arrow.clockwise") { model.startScan() }
                        .disabled(model.scope == nil)
                }
            }
            Text(model.scope?.path ?? "No folder selected")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 320, alignment: .trailing)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let result = model.result, model.phase != .scanning {
            let when = result.finishedAt.formatted(date: .abbreviated, time: .shortened)
            switch result.status {
            case .completed:
                Label("Scan finished \(when): \(result.filesExamined.formatted()) files, \(SizeFormat.string(result.bytesExamined)) on disk (accessible items only).",
                      systemImage: "checkmark.circle")
            case .cancelled:
                Label("Scan cancelled \(when). Results are partial.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            case .failed(let message):
                Label("Scan failed: \(message)", systemImage: "xmark.octagon").foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Results

struct ResultsArea: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let result = model.result, case .failed(let message) = result.status {
            ContentUnavailableView {
                Label("Couldn't scan this folder", systemImage: "lock.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Choose Another Folder…") { model.chooseFolder() }
                Button("Try Again") { model.startScan() }
            }
        } else if let result = model.result {
            LargeFilesView(result: result)
        } else if model.phase == .scanning {
            Spacer()
        } else {
            ContentUnavailableView {
                Label("See what is taking up space", systemImage: "doc.fill")
            } description: {
                Text("Scan first, then review the exact files before removing anything.")
            } actions: {
                if model.scope == nil {
                    Button("Choose a Folder…") { model.chooseFolder() }.buttonStyle(.borderedProminent).tint(.teal)
                } else {
                    Button("Scan this folder") { model.startScan() }.buttonStyle(.borderedProminent).tint(.teal)
                }
            }
        }
    }
}

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    let result: ScanResult

    private let thresholds: [(String, Int64)] = [
        ("10 MB", 10_000_000), ("50 MB", 50_000_000), ("100 MB", 100_000_000),
        ("500 MB", 500_000_000), ("1 GB", 1_000_000_000),
    ]

    var body: some View {
        @Bindable var model = model
        let rows = model.visibleFiles
        let hiddenSelected = model.selection.count - rows.filter { model.isSelected($0) }.count

        VStack(spacing: 0) {
            HStack {
                TextField("Search by name", text: $model.searchText).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Picker("Type", selection: $model.kindFilter) {
                    Text("All types").tag(FileKind?.none)
                    ForEach(FileKind.allCases) { Text($0.rawValue).tag(FileKind?.some($0)) }
                }.frame(maxWidth: 220)
                Picker("Not modified for", selection: $model.minimumAgeDays) {
                    Text("Any age").tag(0); Text("90+ days").tag(90); Text("1+ year").tag(365)
                }.frame(maxWidth: 190)
                Picker("At least", selection: $model.thresholdBytes) {
                    ForEach(thresholds, id: \.1) { Text($0.0).tag($0.1) }
                }.frame(maxWidth: 160)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            if rows.isEmpty {
                ContentUnavailableView(
                    result.status.isPartial ? "No large files found so far" : "No matching files",
                    systemImage: "doc.questionmark",
                    description: Text(emptyHint)
                )
            } else {
                Table(rows, sortOrder: $model.sortOrder) {
                    TableColumn("Select") { file in
                        Toggle("Select \(file.name)", isOn: Binding(
                            get: { model.isSelected(file) }, set: { model.setSelected(file, $0) }
                        )).labelsHidden()
                    }.width(50)
                    TableColumn("Name", value: \.name) { file in
                        VStack(alignment: .leading) {
                            Text(file.name).lineLimit(1)
                            Text(file.url.deletingLastPathComponent().path)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                    }
                    TableColumn("Type") { Text($0.kind.rawValue) }.width(min: 80, ideal: 120)
                    TableColumn("Size on Disk", value: \.allocatedSize) { Text(SizeFormat.string($0.allocatedSize)) }
                        .width(min: 80, ideal: 100)
                    TableColumn("Modified", value: \.modified) {
                        Text($0.modified.formatted(date: .abbreviated, time: .omitted))
                    }.width(min: 90, ideal: 110)
                }
                .contextMenu(forSelectionType: String.self) { _ in } primaryAction: { _ in }
            }

            Divider()
            footer(hiddenSelected: hiddenSelected, shown: rows.count)
        }
    }

    private var emptyHint: String {
        result.status.isPartial
            ? "The scan was cancelled, so results are partial."
            : "Try lowering the size threshold or clearing the filters. \(result.filesExamined.formatted()) files were examined."
    }

    private func footer(hiddenSelected: Int, shown: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(shown.formatted()) shown\(result.truncated ? " · only the largest \(result.files.count.formatted()) are kept" : "")")
                if result.skippedCount > 0 {
                    Text("\(result.skippedCount.formatted()) item(s) couldn't be read and were skipped")
                        .foregroundStyle(.orange)
                }
                if hiddenSelected > 0 {
                    Text("\(hiddenSelected) selected item(s) are hidden by filters")
                }
            }
            .font(.caption)
            Spacer()
            Text("\(model.selection.count) selected · \(SizeFormat.string(model.selectedBytes))").numeric(model.selectedBytes)
            Button("Deselect All") { model.selection = [] }.disabled(model.selection.isEmpty)
            Button("Review…") { model.showingReview = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.selection.isEmpty)
        }
        .padding(12)
    }
}

// MARK: - Review & report

struct ReviewSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let files = model.selectedFiles
        VStack(alignment: .leading, spacing: 12) {
            Text("Review Cleanup").font(.title2.bold())
            Text("\(files.count) file(s) · about \(SizeFormat.string(model.selectedBytes)) will be moved to the Trash. Nothing is permanently deleted, and you can restore items from the Trash. Files that moved or changed since the scan will be skipped.")
                .fixedSize(horizontal: false, vertical: true)
            List(files) { file in
                HStack {
                    VStack(alignment: .leading) {
                        Text(file.name).lineLimit(1)
                        Text(file.url.path).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(SizeFormat.string(file.allocatedSize))
                    Button("Remove from selection", systemImage: "minus.circle") { model.setSelected(file, false) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
            .frame(minHeight: 240)
            HStack {
                Button("Cancel", role: .cancel) { model.showingReview = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if model.isCleaning { ProgressView().controlSize(.small) }
                Button("Move \(files.count) to Trash", role: .destructive) { model.executeCleanup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(files.isEmpty || model.isCleaning)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 440)
        .onChange(of: files.isEmpty) { _, empty in if empty { model.showingReview = false } }
    }
}

struct ReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let report = model.report {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cleanup Results").font(.title2.bold())
                Label("\(report.completed.count) moved to Trash (about \(SizeFormat.string(report.estimatedMovedBytes)), an estimate; check available space on the dashboard)", systemImage: "checkmark.circle")
                Label("\(report.skipped.count) skipped", systemImage: "arrow.uturn.right.circle")
                Label("\(report.failed.count) failed", systemImage: "xmark.octagon")
                List(report.results.filter { $0.outcome != .completed }) { item in
                    VStack(alignment: .leading) {
                        Text(item.file.name)
                        Text(describe(item.outcome)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 120)
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
            .padding(20)
            .frame(minWidth: 520, minHeight: 360)
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
