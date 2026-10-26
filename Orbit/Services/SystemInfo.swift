//
//  SystemInfo.swift
//  Orbit
//

import Darwin
import Foundation

nonisolated struct MemorySnapshot: Sendable {
    var total: UInt64
    var wired: UInt64
    var active: UInt64
    var inactive: UInt64
    var compressed: UInt64
    var free: UInt64
}

nonisolated struct StartupItem: Identifiable, Hashable, Sendable {
    var id: String { plistURL.path }
    let plistURL: URL
    let label: String
    let program: String?
    let programExists: Bool
    let scope: String
    let runsAtLoad: Bool
}

/// Read-only system readings. Orbit never changes system state from these.
nonisolated enum SystemInfo {
    static func memory() -> MemorySnapshot? {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &size, nil, 0) == 0 else { return nil }
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        return MemorySnapshot(total: total, wired: UInt64(stats.wire_count) * page, active: UInt64(stats.active_count) * page,
                              inactive: UInt64(stats.inactive_count) * page, compressed: UInt64(stats.compressor_page_count) * page,
                              free: UInt64(stats.free_count) * page)
    }

    static func loadAverages() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : []
    }

    static func startupItems(home: URL) -> [StartupItem] {
        let dirs: [(URL, String)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), "User launch agent"),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "System-wide launch agent"),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "System-wide launch daemon"),
        ]
        var items: [StartupItem] = []
        for (dir, scope) in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: []) else { continue }
            for file in files where file.pathExtension == "plist" {
                guard let plist = NSDictionary(contentsOf: file) else { continue }
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                items.append(StartupItem(
                    plistURL: file, label: (plist["Label"] as? String) ?? file.deletingPathExtension().lastPathComponent,
                    program: program, programExists: program.map { FileManager.default.fileExists(atPath: $0) } ?? true,
                    scope: scope, runsAtLoad: (plist["RunAtLoad"] as? Bool) ?? false))
            }
        }
        return items.sorted { ($0.programExists ? 1 : 0, $0.label) < ($1.programExists ? 1 : 0, $1.label) }
    }
}
