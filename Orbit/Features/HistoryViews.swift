//
//  HistoryViews.swift
//  Orbit
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "History", subtitle: "Every cleanup Orbit has performed, stored only on this Mac",
                           symbol: "clock.arrow.circlepath", trailing: AnyView(
                    Button("Clear History…", role: .destructive) { confirmClear = true }.disabled(history.entries.isEmpty)))
                if !history.entries.isEmpty {
                    Label("\(history.entries.count) operation(s), \(SizeFormat.string(history.totalMovedBytes)) moved to the Trash in total",
                          systemImage: "tray.full")
                    Text("Sizes are what was moved to the Trash. Space is freed only once the Trash is emptied.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            Divider()
            if history.entries.isEmpty {
                ContentUnavailableView("No cleanups yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Completed, skipped and failed items will be listed here after your first cleanup."))
            } else {
                List(history.entries) { entry in
                    DisclosureGroup {
                        ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                            HistoryLineRow(line: line)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.source).fontWeight(.medium)
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.problemCount > 0 {
                                Text("\(entry.problemCount) not moved").font(.caption).foregroundStyle(.orange)
                            }
                            Text(SizeFormat.string(entry.movedBytes)).monospacedDigit().numeric(entry.movedBytes)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Clear the cleanup history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: { Text("This only removes Orbit's log. It does not touch any files or the Trash.") }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(DevCleanupModel.self) private var dev
    @Environment(DuplicatesModel.self) private var duplicates
    @Environment(SimilarPhotosModel.self) private var photos
    @AppStorage("appearance") private var appearance = "system"
    @State private var excluded = Exclusions.paths
    @State private var picking = false
    @State private var hasFDA = false

    private var grantedFolders: [(String, URL)] {
        var list: [(String, URL)] = []
        if let home = dev.home { list.append(("Home folder (Smart Care)", home)) }
        if let scope = model.scope { list.append(("Space Explorer / Large Files", scope)) }
        if let scope = duplicates.scope { list.append(("Duplicate Finder", scope)) }
        if let scope = photos.scope { list.append(("Similar Photos", scope)) }
        return list
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Light", systemImage: "sun.max").tag("light")
                    Label("Dark", systemImage: "moon").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("Full Disk Access") {
                    HStack(spacing: 8) {
                        Label(hasFDA ? "Allowed" : "Not allowed", systemImage: hasFDA ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasFDA ? .green : .orange)
                        if !hasFDA { Button("Open System Settings") { model.openFullDiskAccessSettings() } }
                    }
                }
                if grantedFolders.isEmpty {
                    Text("No folders granted yet. Orbit asks when a scan needs one.").foregroundStyle(.secondary)
                }
                ForEach(grantedFolders, id: \.1.path) { label, url in
                    LabeledContent(label) {
                        Text(url.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Access")
            } footer: {
                Text("macOS only lets Orbit read folders you choose. Access lasts for this session; Orbit asks again next time.")
            }

            Section {
                if excluded.isEmpty {
                    Text("No exclusions. Add a project or folder you want Orbit to always leave alone.").foregroundStyle(.secondary)
                }
                ForEach(excluded, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.secondary)
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") { remove(path) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                Button("Add Folder…", systemImage: "plus") { picking = true }
            } header: {
                Text("Excluded folders")
            } footer: {
                Text("Excluded folders are hidden from scan results, and Orbit re-checks this list immediately before moving anything to the Trash.")
            }

            Section("About") {
                LabeledContent("App", value: info("CFBundleName") ?? "Orbit")
                LabeledContent("Version", value: "\(info("CFBundleShortVersionString") ?? "1.0") (\(info("CFBundleVersion") ?? "1"))")
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("Developer", value: "Prateek Thakur")
                LabeledContent("GitHub") {
                    Link("github.com/prateekthakur272", destination: URL(string: "https://github.com/prateekthakur272")!)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { hasFDA = model.hasFullDiskAccess }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFDA = model.hasFullDiskAccess
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let path = url.standardizedFileURL.path
            guard !excluded.contains(path) else { return }
            Motion.run { excluded.append(path) }
            Exclusions.paths = excluded
        }
    }

    private func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private func remove(_ path: String) {
        Motion.run { excluded.removeAll { $0 == path } }
        Exclusions.paths = excluded
    }
}

private struct HistoryLineRow: View {
    let line: HistoryEntry.Line

    private var symbol: String {
        switch line.status {
        case "moved": "checkmark.circle.fill"
        case "skipped": "minus.circle"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch line.status {
        case "moved": .green
        case "skipped": .secondary
        default: .orange
        }
    }

    var body: some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                Text(line.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let detail = line.detail { Text(detail).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Text(SizeFormat.string(line.bytes)).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
