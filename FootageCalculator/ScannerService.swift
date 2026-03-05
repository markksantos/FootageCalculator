import Foundation
import AVFoundation

// MARK: - Types

enum ScanState: Equatable {
    case idle
    case scanning(scanned: Int, total: Int)
    case results
}

enum FileCategory: String, CaseIterable {
    case video, audio, image, other
}

struct ScanResults {
    var videoDuration: TimeInterval = 0
    var audioDuration: TimeInterval = 0
    var videoCount: Int = 0
    var audioCount: Int = 0
    var imageCount: Int = 0
    var otherCount: Int = 0
    var videoUnknown: Int = 0
    var audioUnknown: Int = 0
}

// MARK: - File Classification

private let videoExtensions: Set<String> = [
    "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v",
    "mpg", "mpeg", "3gp", "ts", "mts", "m2ts", "vob", "ogv",
    "mxf", "r3d", "braw", "prores",
]

private let audioExtensions: Set<String> = [
    "mp3", "wav", "aac", "flac", "ogg", "wma", "m4a",
    "aiff", "aif", "opus",
]

private let imageExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif",
    "webp", "heic", "heif", "raw", "cr2", "nef", "arw", "psd",
]

func classify(_ url: URL) -> FileCategory {
    let ext = url.pathExtension.lowercased()
    if videoExtensions.contains(ext) { return .video }
    if audioExtensions.contains(ext) { return .audio }
    if imageExtensions.contains(ext) { return .image }
    return .other
}

// MARK: - Duration Formatting

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}

// MARK: - Scanner Service

@Observable
final class ScannerService {
    var state: ScanState = .idle
    var results = ScanResults()
    var includeSubfolders = true

    private var scanTask: Task<Void, Never>?

    func scan(urls: [URL]) {
        cancel()
        state = .scanning(scanned: 0, total: 0)
        results = ScanResults()

        scanTask = Task { [includeSubfolders] in
            // Collect all file URLs
            var fileURLs: [URL] = []
            for url in urls {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                if isDir.boolValue {
                    fileURLs.append(contentsOf: collectFiles(in: url, recursive: includeSubfolders))
                } else {
                    fileURLs.append(url)
                }
            }

            let total = fileURLs.count
            if total == 0 {
                await MainActor.run { self.state = .results }
                return
            }

            await MainActor.run {
                self.state = .scanning(scanned: 0, total: total)
            }

            var localResults = ScanResults()

            for (index, fileURL) in fileURLs.enumerated() {
                if Task.isCancelled { return }

                let category = classify(fileURL)
                switch category {
                case .video:
                    localResults.videoCount += 1
                    if let duration = await getDuration(for: fileURL) {
                        localResults.videoDuration += duration
                    } else {
                        localResults.videoUnknown += 1
                    }
                case .audio:
                    localResults.audioCount += 1
                    if let duration = await getDuration(for: fileURL) {
                        localResults.audioDuration += duration
                    } else {
                        localResults.audioUnknown += 1
                    }
                case .image:
                    localResults.imageCount += 1
                case .other:
                    localResults.otherCount += 1
                }

                if index % 5 == 0 || index == total - 1 {
                    let scanned = index + 1
                    let snapshot = localResults
                    await MainActor.run {
                        self.results = snapshot
                        self.state = .scanning(scanned: scanned, total: total)
                    }
                }
            }

            let finalResults = localResults
            await MainActor.run {
                self.results = finalResults
                self.state = .results
            }
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        state = .idle
    }

    func reset() {
        cancel()
        results = ScanResults()
    }
}

// MARK: - File Collection

private func collectFiles(in directory: URL, recursive: Bool) -> [URL] {
    let fm = FileManager.default
    var result: [URL] = []

    guard let enumerator = fm.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return result
    }

    for case let fileURL as URL in enumerator {
        if !recursive {
            // Only include items at the top level
            if fileURL.deletingLastPathComponent().path != directory.path {
                enumerator.skipDescendants()
                continue
            }
        }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
        if !isDir.boolValue {
            result.append(fileURL)
        }
    }

    return result
}

// MARK: - AVFoundation Duration

private func getDuration(for url: URL) -> TimeInterval? {
    let asset = AVURLAsset(url: url)
    let duration = asset.duration
    if duration == .invalid || duration == .zero || duration == .indefinite {
        return nil
    }
    let seconds = CMTimeGetSeconds(duration)
    return seconds.isFinite && seconds > 0 ? seconds : nil
}
