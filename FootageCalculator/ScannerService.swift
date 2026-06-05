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

struct ScanResults: Equatable {
    var videoDuration: TimeInterval = 0
    var audioDuration: TimeInterval = 0
    var videoCount: Int = 0
    var audioCount: Int = 0
    var imageCount: Int = 0
    var otherCount: Int = 0
    var videoUnknown: Int = 0
    var audioUnknown: Int = 0

    var totalFiles: Int { videoCount + audioCount + imageCount + otherCount }
    var totalDuration: TimeInterval { videoDuration + audioDuration }

    /// A plain-text summary suitable for copying to the clipboard or saving.
    var plainTextSummary: String {
        var lines: [String] = ["Footage Calculator — Scan Summary", ""]
        lines.append("Total duration: \(formatDuration(totalDuration))")
        lines.append("Total files:    \(totalFiles)")
        lines.append("")
        lines.append("Video:  \(videoCount) file\(videoCount == 1 ? "" : "s") — \(formatDuration(videoDuration))"
            + (videoUnknown > 0 ? " (\(videoUnknown) unknown)" : ""))
        lines.append("Audio:  \(audioCount) file\(audioCount == 1 ? "" : "s") — \(formatDuration(audioDuration))"
            + (audioUnknown > 0 ? " (\(audioUnknown) unknown)" : ""))
        lines.append("Images: \(imageCount) file\(imageCount == 1 ? "" : "s")")
        lines.append("Other:  \(otherCount) file\(otherCount == 1 ? "" : "s")")
        return lines.joined(separator: "\n")
    }
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

@MainActor
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

        let recursive = includeSubfolders
        scanTask = Task { [weak self] in
            // Hold a security-scoped grant on each top-level (user-selected) URL
            // for the WHOLE scan — collection AND duration reads of children
            // both require the parent's access to stay open under App Sandbox.
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }

            // Collect all file URLs off the main actor.
            let fileURLs = await Task.detached(priority: .userInitiated) {
                collectFiles(from: urls, recursive: recursive)
            }.value

            guard let self, !Task.isCancelled else { return }

            let total = fileURLs.count
            if total == 0 {
                self.state = .results
                return
            }

            self.state = .scanning(scanned: 0, total: total)

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
                    self.results = localResults
                    self.state = .scanning(scanned: index + 1, total: total)
                }
            }

            if Task.isCancelled { return }
            self.results = localResults
            self.state = .results
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

/// Expands a mix of file and directory URLs into a flat list of regular-file URLs.
///
/// Callers are responsible for holding any required security-scoped access on
/// the top-level `urls` for the lifetime of the scan (see `ScannerService.scan`).
func collectFiles(from urls: [URL], recursive: Bool) -> [URL] {
    let fm = FileManager.default
    var result: [URL] = []

    for url in urls {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            result.append(contentsOf: collectFiles(in: url, recursive: recursive, fm: fm))
        } else if fm.fileExists(atPath: url.path) {
            result.append(url)
        }
    }

    return result
}

private func collectFiles(in directory: URL, recursive: Bool, fm: FileManager) -> [URL] {
    var result: [URL] = []

    guard let enumerator = fm.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
    ) else {
        return result
    }

    for case let fileURL as URL in enumerator {
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        if values?.isRegularFile == true {
            result.append(fileURL)
        }
    }

    return result
}

// MARK: - AVFoundation Duration

/// Loads a media asset's duration in seconds, or `nil` if it can't be read.
///
/// Uses the modern async `load(.isPlayable)` / `load(.duration)` API
/// (`AVAsset.duration` is deprecated since macOS 13) so the call genuinely
/// suspends instead of blocking, and unreadable/corrupt files fail gracefully.
private func getDuration(for url: URL) async -> TimeInterval? {
    let asset = AVURLAsset(url: url)
    do {
        let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
        guard isPlayable else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : nil
    } catch {
        return nil
    }
}
