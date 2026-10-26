//
//  SystemViews.swift
//  Orbit
//

import AppKit
import Charts
import SwiftUI

// MARK: - Trash Bins

struct TrashBinsView: View {
    @Environment(DevCleanupModel.self) private var dev
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(title: "Trash Bins", subtitle: "What's in your Trash, and a separate, confirmed way to empty it",
                           symbol: "trash.fill", trailing: AnyView(HStack {
                    Button("Refresh", systemImage: "arrow.clockwise") { if dev.ensureAccess() { dev.refreshTrash() } }
                    Button("Empty Trash…", role: .destructive) { confirm = true }
                        .disabled((dev.trash?.itemCount ?? 0) == 0 || dev.isCleaning)
                }))
                if let trash = dev.trash {
                    Label("\(trash.itemCount) item(s), \(SizeFormat.string(trash.bytes))", systemImage: "trash")
                }
                if let summary = dev.emptyTrashSummary { Text(summary).font(.caption).foregroundStyle(.secondary) }
                Text("Emptying the Trash permanently deletes everything in it. Orbit never does this as part of another cleanup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            if dev.home == nil {
                ContentUnavailableView {
                    Label("Check your Trash", systemImage: "trash.fill")
                } description: { Text("Orbit needs access to your home folder to read the Trash.") } actions: {
                    Button("Grant Access") { if dev.ensureAccess() { dev.refreshTrash() } }.buttonStyle(.borderedProminent).tint(.teal)
                }
            } else if !dev.trashReadable {
                ContentUnavailableView("Trash can't be read", systemImage: "lock.slash",
                                       description: Text("macOS protects the Trash. Grant Orbit Full Disk Access in System Settings, then refresh."))
            } else if dev.trashEntries.isEmpty {
                ContentUnavailableView("Trash is empty", systemImage: "checkmark.seal")
            } else {
                List(dev.trashEntries) { e in
                    HStack {
                        Image(systemName: e.isDirectory ? "folder" : "doc").foregroundStyle(.secondary)
                        Text(e.name).lineLimit(1)
                        Spacer()
                        Text(SizeFormat.string(e.bytes)).monospacedDigit()
                    }
                }
            }
        }
        .task { if dev.home != nil { dev.refreshTrash() } }
        .confirmationDialog("Permanently empty the Trash?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Empty Trash Permanently", role: .destructive) { dev.emptyTrash() }
        } message: {
            Text("This permanently deletes everything in your Trash, including items not moved by Orbit. It can't be undone.")
        }
    }
}

// MARK: - Protection

@Observable
final class ProtectionModel {
    private(set) var items: [StartupItem] = []
    private(set) var loaded = false

    func load(home: URL) {
        Task {
            items = await Task.detached { SystemInfo.startupItems(home: home) }.value
            loaded = true
        }
    }
}

struct ProtectionView: View {
    @Environment(ProtectionModel.self) private var model
    @Environment(DevCleanupModel.self) private var dev

    private let panes: [(String, String, String)] = [
        ("Privacy & Security", "lock.shield", "com.apple.preference.security?Privacy"),
        ("FileVault", "key.fill", "com.apple.preference.security?FileVault"),
        ("Firewall", "flame", "com.apple.Network-Settings.extension?Firewall"),
        ("Login Items", "person.crop.circle.badge.checkmark", "com.apple.LoginItems-Settings.extension"),
        ("Full Disk Access", "externaldrive.badge.person.crop", "com.apple.preference.security?Privacy_AllFiles"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(title: "Protection", subtitle: "Review what starts on your Mac and jump to the right privacy settings",
                           symbol: "shield.fill", trailing: AnyView(Button("Scan Startup Items", systemImage: "arrow.clockwise") { scan() }
                    .buttonStyle(.borderedProminent).tint(.teal)))
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(panes, id: \.0) { title, symbol, pane in
                            Button(title, systemImage: symbol) {
                                if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) }
                            }
                        }
                    }
                }
                Text("Orbit doesn't claim your Mac is “protected” and doesn't scan for malware. This page is read-only: it lists launch agents and daemons so you can spot ones whose program is missing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            if !model.loaded {
                ContentUnavailableView {
                    Label("Review startup items", systemImage: "shield.fill")
                } description: { Text("Lists launch agents and daemons that run in the background, so you can see what's installed.") } actions: {
                    Button("Scan Startup Items") { scan() }.buttonStyle(.borderedProminent).tint(.teal)
                }
            } else if model.items.isEmpty {
                ContentUnavailableView("No startup items found", systemImage: "checkmark.seal")
            } else {
                List(model.items) { item in
                    HStack(alignment: .top) {
                        Image(systemName: item.programExists ? "gearshape" : "exclamationmark.triangle.fill")
                            .foregroundStyle(item.programExists ? Color.secondary : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(.headline)
                            Text("\(item.scope)\(item.runsAtLoad ? " · runs at load" : "")").font(.caption).foregroundStyle(.secondary)
                            Text(item.program ?? "No program listed").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            if !item.programExists {
                                Text("The program this item launches is missing. It's probably left over from an uninstalled app.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.plistURL]) }.buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func scan() { model.load(home: dev.home ?? DevCleanupModelHome.home) }
}

// MARK: - Performance

struct PerformanceView: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                PageHeader(title: "Performance", subtitle: "Live, read-only readings of memory, load and system state",
                           symbol: "gauge.with.dots.needle.67percent")
                Text("These are measurements only. Orbit doesn't “free memory” or “boost” anything: macOS manages memory itself, and tools claiming otherwise generally don't help.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                ScrollView { content.padding(20) }
            }
        }
    }

    private struct Slice: Identifiable { let id: String; let bytes: UInt64; let color: Color }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let m = SystemInfo.memory() {
                let slices = [
                    Slice(id: "Wired", bytes: m.wired, color: .red), Slice(id: "Active", bytes: m.active, color: .orange),
                    Slice(id: "Inactive", bytes: m.inactive, color: .yellow), Slice(id: "Compressed", bytes: m.compressed, color: .purple),
                    Slice(id: "Free", bytes: m.free, color: .green),
                ]
                Card {
                    VStack(alignment: .leading) {
                        Text("Memory · \(SizeFormat.string(Int64(m.total))) installed").font(.headline)
                        HStack(spacing: 24) {
                            Chart(slices) { s in
                                SectorMark(angle: .value("Bytes", Double(s.bytes)), innerRadius: .ratio(0.6), angularInset: 1).foregroundStyle(s.color)
                            }.frame(width: 160, height: 160)
                            VStack(spacing: 6) {
                                ForEach(slices) { s in
                                    HStack {
                                        Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(s.color)
                                        Text(s.id); Spacer(); Text(SizeFormat.string(Int64(s.bytes))).monospacedDigit()
                                    }
                                }
                            }.frame(maxWidth: 300)
                        }
                        .accessibilityElement(children: .combine)
                        Text("Inactive memory is cached data macOS reclaims when needed; it isn't a problem.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Memory statistics are unavailable.").foregroundStyle(.secondary)
            }
            Card {
                let load = SystemInfo.loadAverages()
                VStack(alignment: .leading, spacing: 6) {
                    Text("System").font(.headline)
                    row("CPU cores", "\(ProcessInfo.processInfo.activeProcessorCount) active of \(ProcessInfo.processInfo.processorCount)")
                    row("Load average (1 / 5 / 15 min)", load.count == 3 ? load.map { String(format: "%.2f", $0) }.joined(separator: " / ") : "Unavailable")
                    row("Uptime", Duration.seconds(ProcessInfo.processInfo.systemUptime).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated)))
                    row("Thermal state", thermal)
                    row("Low Power Mode", ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off")
                }
            }
        }
    }

    private var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "Normal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).monospacedDigit() }
    }
}
