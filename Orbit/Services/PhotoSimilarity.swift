//
//  PhotoSimilarity.swift
//  Orbit
//

import Foundation
import ImageIO
import Vision

nonisolated struct SimilarPhotoGroup: Identifiable, Sendable {
    let id: Int
    var files: [ScannedFile]
}

nonisolated struct PhotoResult: Sendable {
    let scope: URL
    var status: ScanStatus
    var groups: [SimilarPhotoGroup]
    var photosExamined: Int
    var truncated: Bool
}

/// Groups visually similar images using on-device Vision feature prints. Matches are suggestions only.
nonisolated struct PhotoSimilarityFinder: Sendable {
    var maxPhotos = 2_500
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]

    func find(root: URL, maxDistance: Float, progress: @escaping @Sendable (Int, Int) -> Void) async -> PhotoResult {
        let task = Task.detached(priority: .userInitiated) { run(root: root, maxDistance: maxDistance, progress: progress) }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func run(root: URL, maxDistance: Float, progress: @Sendable (Int, Int) -> Void) -> PhotoResult {
        var result = PhotoResult(scope: root, status: .completed, groups: [], photosExamined: 0, truncated: false)
        guard (try? FileManager.default.contentsOfDirectory(atPath: root.path)) != nil else {
            result.status = .failed("Orbit can't read this folder. Choose it again, or pick a different folder.")
            return result
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                               options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return result }
        var photos: [ScannedFile] = []
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { result.status = .cancelled; return result }
            guard Self.imageExtensions.contains(url.pathExtension.lowercased()),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, v.isSymbolicLink != true,
                  let identity = FileIdentity.current(at: url) else { continue }
            if photos.count >= maxPhotos { result.truncated = true; break }
            photos.append(ScannedFile(url: url, name: url.lastPathComponent, kind: .image,
                                      allocatedSize: Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0), logicalSize: Int64(v.fileSize ?? 0),
                                      modified: v.contentModificationDate ?? .distantPast, identity: identity))
        }

        var prints: [(ScannedFile, VNFeaturePrintObservation)] = []
        for (index, photo) in photos.enumerated() {
            if Task.isCancelled { result.status = .cancelled; result.photosExamined = index; return result }
            if index % 10 == 0 { progress(index, photos.count) }
            guard let print = Self.featurePrint(for: photo.url) else { continue }
            prints.append((photo, print))
        }
        result.photosExamined = photos.count

        // Union-find over pairs within distance.
        var parent = Array(0..<prints.count)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        for i in 0..<prints.count {
            if i % 50 == 0 && Task.isCancelled { result.status = .cancelled; return result }
            for j in (i + 1)..<max(prints.count, i + 1) {
                var distance: Float = 0
                if (try? prints[i].1.computeDistance(&distance, to: prints[j].1)) != nil, distance <= maxDistance {
                    parent[find(i)] = find(j)
                }
            }
        }
        var clusters: [Int: [ScannedFile]] = [:]
        for i in 0..<prints.count { clusters[find(i), default: []].append(prints[i].0) }
        result.groups = clusters.values.filter { $0.count > 1 }
            .map { $0.sorted { $0.modified < $1.modified } }
            .sorted { $0.reduce(0) { $0 + $1.allocatedSize } > $1.reduce(0) { $0 + $1.allocatedSize } }
            .enumerated().map { SimilarPhotoGroup(id: $0.offset, files: $0.element) }
        return result
    }

    static func featurePrint(for url: URL) -> VNFeaturePrintObservation? {
        guard let thumb = thumbnail(url: url, maxPixel: 512) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: thumb, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first
    }

    static func thumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
