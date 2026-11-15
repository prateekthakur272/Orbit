# Orbit

A native macOS app for reclaiming disk space and keeping your Mac tidy. Orbit scans your system, shows you exactly what is taking up room, and moves cleanup candidates to the Trash so you can review before anything is gone for good.

Built with SwiftUI.

<img width="1470" height="923" alt="Screenshot 2026-10-26 at 9 18 04 PM" src="https://github.com/user-attachments/assets/407a1586-9c14-4b9e-8ae2-adfe9698f82f" />


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

<img width="1470" height="923" alt="Screenshot 2026-10-26 at 9 17 46 PM" src="https://github.com/user-attachments/assets/cd821862-fa1b-4620-ae2d-16975fce4897" />
<img width="1470" height="923" alt="Screenshot 2026-10-26 at 9 18 23 PM" src="https://github.com/user-attachments/assets/81ee415d-b694-4919-8eac-2b56867d260f" />
<img width="1470" height="923" alt="Screenshot 2026-10-26 at 9 18 38 PM" src="https://github.com/user-attachments/assets/54b0a0ec-3f73-42c7-894d-c2272ca29fce" />


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
