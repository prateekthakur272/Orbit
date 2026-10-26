//
//  OrbitApp.swift
//  Orbit
//
//  Created by ENT-0554 on 26/10/26.
//

import SwiftUI

@main
struct OrbitApp: App {
    @State private var model = AppModel()
    @State private var dev = DevCleanupModel()
    @State private var explorer = SpaceExplorerModel()
    @State private var duplicates = DuplicatesModel()
    @State private var photos = SimilarPhotosModel()
    @State private var apps = AppsModel()
    @State private var protection = ProtectionModel()
    @State private var history = HistoryModel.shared
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .environment(dev)
                .environment(explorer)
                .environment(duplicates)
                .environment(photos)
                .environment(apps)
                .environment(protection)
                .environment(history)
                .frame(minWidth: 900, minHeight: 600)
                .toastHost()
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .commands {
            CommandMenu("Go") {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, item in
                    Button(item.0) { Motion.run { model.section = item.1 } }
                        .keyboardShortcut(KeyEquivalent(Character("\((index + 1) % 10)")), modifiers: .command)
                }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(dev)
                .environment(duplicates)
                .environment(photos)
                .frame(width: 560, height: 440)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
    }

    private var shortcuts: [(String, AppModel.Section)] {
        [("Smart Care", .smartCare), ("Developer Overview", .group(nil)), ("Uninstaller", .uninstaller),
         ("Space Explorer", .spaceExplorer), ("Duplicate Finder", .duplicates), ("Similar Photos", .similarPhotos),
         ("Trash Bins", .trashBins), ("Large & Old Files", .largeFiles), ("Protection", .protection), ("Performance", .performance)]
    }
}
