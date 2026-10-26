# Orbit

A native macOS app for reclaiming disk space and keeping your Mac tidy. Orbit scans your system, shows you exactly what is taking up room, and moves cleanup candidates to the Trash so you can review before anything is gone for good.

Built with SwiftUI.

<!-- Replace the placeholders below with real screenshots (e.g. docs/screenshots/*.png). -->
<p align="center">
  <img src="docs/screenshots/hero.png" alt="Orbit main window" width="800">
</p>

## Features

- **Smart Care**: one-click scan across the common junk categories.
- **System cleanup**: system junk (logs, crash reports), user caches, Mail attachments and leftovers from uninstalled apps.
- **Developer cleanup**: Xcode (DerivedData, device support, simulators, archives), Homebrew, Node tooling (npm, Yarn, pnpm, Bun, Deno), Docker caches, language toolchains (Gradle, Maven, Python, Rust, Go), AI apps and editors, and project build artifacts such as `node_modules`, `build` and `target`.
- **Space Explorer**: visualize where your disk space is going.
- **Large & Old Files**: find big files you haven't touched in a while.
- **Duplicate Finder** and **Similar Photos**: reclaim space from copies and near-copies.
- **Uninstaller**: remove apps together with their support files, containers and caches.
- **App Updates**, **Trash Bins**, **Protection**, **Performance** and **History** views.

> Orbit scans are read-only. Docker container data is shown but never removed.

## Screenshots

| Smart Care | Developer Cleanup |
| :---: | :---: |
| ![Smart Care](docs/screenshots/smart-care.png) | ![Developer Cleanup](docs/screenshots/developer-cleanup.png) |

| Space Explorer | Duplicate Finder |
| :---: | :---: |
| ![Space Explorer](docs/screenshots/space-explorer.png) | ![Duplicate Finder](docs/screenshots/duplicates.png) |

| Similar Photos | Uninstaller |
| :---: | :---: |
| ![Similar Photos](docs/screenshots/similar-photos.png) | ![Uninstaller](docs/screenshots/uninstaller.png) |

## Requirements

- macOS (the project's deployment target is set in `Orbit.xcodeproj`)
- Xcode with a matching SDK

## Build & Run

```sh
git clone <repo-url>
cd Orbit
open Orbit.xcodeproj
```

Select the **Orbit** scheme and press **Run** (⌘R).

## Permissions

Orbit runs in the macOS App Sandbox, which only grants access to folders you explicitly choose. On first use you will be asked to select:

- your **home folder**, for developer and system cleanup scans
- the **disk** or **/Applications**, for Space Explorer and the Uninstaller

Nothing is accessed until you grant it.

## Project Structure

```
Orbit/
├── OrbitApp.swift      App entry point
├── ContentView.swift   Sidebar and navigation
├── Domain/             Models (items, groups, scan results)
├── Features/           SwiftUI views and view models, one per feature
└── Services/           Scanners, executors and storage
                        (DevScanner, FileScanner, DuplicateFinder,
                         PhotoSimilarity, AppInventory, TrashService,
                         CleanupExecutor, HistoryStore, SystemInfo)
```

## License

Add a license here.
