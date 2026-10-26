//
//  AppsViews.swift
//  Orbit
//

import AppKit
import SwiftUI

@Observable
final class AppsModel {
    struct Plan: Identifiable {
        var id: String { app.id }
        let app: AppInfo
        let related: [RelatedFile]
        var selection: Set<String>
        var appItem: DevItem { AppInventory.item(for: app) }
        var chosen: [DevItem] { [appItem] + related.filter { selection.contains($0.id) }.map(\.item) }
        var bytes: Int64 { chosen.reduce(0) { $0 + $1.bytes } }
    }

    private(set) var apps: [AppInfo] = []
    private(set) var loaded = false
    private(set) var loading = false
    var searchText = ""
    var plan: Plan?
    var report: DevCleanupReport?
    private(set) var isWorking = false
    private var grantedRoots: [URL] = []

    var visibleApps: [AppInfo] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(q) }
    }

    func load() {
        guard !loading else { return }
        loading = true
        Task {
            apps = await AppInventory.installedApps(roots: AppInventory.applicationRoots + grantedRoots)
            loaded = true
            loading = false
        }
    }

    /// Reading and modifying /Applications under the sandbox needs the user to select it once.
    func grantApplicationsAccess() {
        guard let url = FolderPicker.choose(message: "Select the Applications folder so Orbit can list apps and, after your review, move them to the Trash.",
                                            start: URL(fileURLWithPath: "/Applications")) else { return }
        grantedRoots.append(url)
        load()
    }

    func beginUninstall(_ app: AppInfo, home: URL) {
        let related = AppInventory.relatedFiles(for: app, home: home)
        plan = Plan(app: app, related: related, selection: Set(related.filter(\.strongMatch).map(\.id)))
    }

    func toggle(_ id: String, _ on: Bool) {
        if on { plan?.selection.insert(id) } else { plan?.selection.remove(id) }
    }

    func executeUninstall(home: URL) {
        guard let plan, !isWorking else { return }
        isWorking = true
        let items = plan.chosen
        var blocked: [String: String] = [:]
        if let id = plan.app.bundleID, !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            blocked[plan.appItem.id] = "The app is running. Quit it first."
        }
        let roots = AppInventory.applicationRoots + grantedRoots
        Task {
            let outcome = await DevCleanupExecutor().execute(items: items, home: home, extraRoots: roots, blocked: blocked)
            if outcome.results.contains(where: { $0.item.id == plan.appItem.id && $0.outcome == .completed }) {
                Motion.run { apps.removeAll { $0.id == plan.app.id } }
                ToastCenter.shared.show("\(plan.app.name) moved to the Trash")
            }
            report = outcome
            HistoryModel.shared.record(source: "Uninstall \(plan.app.name)", report: outcome)
            self.plan = nil
            isWorking = false
        }
    }
}

struct UninstallerView: View {
    @Environment(AppsModel.self) private var apps
    @Environment(DevCleanupModel.self) private var dev

    var body: some View {
        @Bindable var apps = apps
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "Uninstaller", subtitle: "Remove an app together with its support files",
                           symbol: "app.dashed", trailing: AnyView(HStack {
                    TextField("Search apps", text: $apps.searchText).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                    Button("Allow /Applications…") { apps.grantApplicationsAccess() }
                        .help("Needed once so Orbit can see and move apps in /Applications.")
                }))
                Text("Apple's own apps are never listed. Everything moves to the Trash, so you can restore it. Running apps are skipped.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            if apps.loading && apps.apps.isEmpty {
                ProgressView("Reading installed apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if apps.apps.isEmpty {
                ContentUnavailableView("No apps found", systemImage: "app.dashed",
                                       description: Text("Click “Allow /Applications…” so Orbit can read your installed apps."))
            } else {
                List(apps.visibleApps) { app in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 32, height: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(app.name).font(.headline)
                            Text("\(app.version.map { "v\($0) · " } ?? "")\(app.isAppStore ? "App Store" : "Direct download") · \(app.url.deletingLastPathComponent().path)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(SizeFormat.string(app.bytes)).monospacedDigit()
                        Button("Uninstall…") {
                            if dev.ensureAccess(), let home = dev.home { apps.beginUninstall(app, home: home) }
                        }
                    }
                }
            }
        }
        .task { if !apps.loaded { apps.load() } }
        .sheet(item: $apps.plan) { _ in UninstallSheet() }
        .sheet(item: $apps.report) { DevReportContent(report: $0) }
    }
}

struct UninstallSheet: View {
    @Environment(AppsModel.self) private var apps
    @Environment(DevCleanupModel.self) private var dev

    var body: some View {
        if let plan = apps.plan {
            VStack(alignment: .leading, spacing: 12) {
                Text("Uninstall \(plan.app.name)").font(.title2.bold())
                Text("These items will be moved to the Trash. Exact matches for the app's identifier are pre-selected because you chose to uninstall it. Items matched by name only are not, so check them first.")
                    .fixedSize(horizontal: false, vertical: true)
                List {
                    HStack {
                        Label("\(plan.app.name).app", systemImage: "app.fill")
                        Spacer(); Text(SizeFormat.string(plan.app.bytes))
                    }
                    ForEach(plan.related) { rel in
                        HStack(alignment: .top) {
                            Toggle(rel.item.title, isOn: Binding(
                                get: { plan.selection.contains(rel.id) }, set: { apps.toggle(rel.id, $0) }
                            )).labelsHidden()
                            VStack(alignment: .leading) {
                                Text(rel.item.title)
                                Text(rel.item.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                Text(rel.item.reason).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(SizeFormat.string(rel.item.bytes))
                        }
                    }
                }
                .frame(minHeight: 260)
                HStack {
                    Button("Cancel", role: .cancel) { apps.plan = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if apps.isWorking { ProgressView().controlSize(.small) }
                    Button("Move \(plan.chosen.count) Item(s) to Trash (\(SizeFormat.string(plan.bytes)))", role: .destructive) {
                        if let home = dev.home { apps.executeUninstall(home: home) }
                    }
                    .buttonStyle(.borderedProminent).disabled(apps.isWorking)
                }
            }
            .padding(20).frame(minWidth: 640, minHeight: 480)
        }
    }
}

extension DevCleanupReport {
    // Identifiable conformance lives in DeveloperCleanupView.swift.
}

struct AppUpdatesView: View {
    @Environment(AppsModel.self) private var apps
    @State private var filter = 0

    var body: some View {
        let list = apps.apps.filter { filter == 0 || (filter == 1 ? $0.isAppStore : !$0.isAppStore) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "App Updates", subtitle: "Installed apps, their versions and where they came from",
                           symbol: "arrow.triangle.2.circlepath", trailing: AnyView(HStack {
                    Picker("Source", selection: $filter) { Text("All").tag(0); Text("App Store").tag(1); Text("Direct").tag(2) }
                        .pickerStyle(.segmented).frame(maxWidth: 240)
                    Button("Open App Store Updates") {
                        if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
                    }
                }))
                Label("Orbit works offline and doesn't check for new versions itself. App Store apps update from the App Store; for direct downloads, use each app's own “Check for Updates”.",
                      systemImage: "network.slash").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            if list.isEmpty {
                ContentUnavailableView("No apps to show", systemImage: "app.dashed",
                                       description: Text("Open the Uninstaller page and allow access to /Applications to list installed apps."))
            } else {
                List(list) { app in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(app.name).font(.headline)
                            Text(app.bundleID ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(app.version.map { "v\($0)" } ?? "Unknown version").foregroundStyle(.secondary)
                        Label(app.isAppStore ? "App Store" : "Direct", systemImage: app.isAppStore ? "bag" : "arrow.down.circle")
                            .font(.caption).frame(width: 100, alignment: .leading)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }.buttonStyle(.borderless)
                    }
                }
            }
        }
        .task { if !apps.loaded { apps.load() } }
    }
}
