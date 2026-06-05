import XCTest
import AVFoundation
@testable import FootageCalculator

final class ScannerServiceTests: XCTestCase {

    // MARK: - Classification

    func testClassifyVideoExtensions() {
        for ext in ["mp4", "MOV", "mkv", "r3d", "braw", "mxf"] {
            let url = URL(fileURLWithPath: "/tmp/clip.\(ext)")
            XCTAssertEqual(classify(url), .video, "\(ext) should classify as video")
        }
    }

    func testClassifyAudioExtensions() {
        for ext in ["mp3", "WAV", "flac", "m4a", "aiff"] {
            let url = URL(fileURLWithPath: "/tmp/track.\(ext)")
            XCTAssertEqual(classify(url), .audio, "\(ext) should classify as audio")
        }
    }

    func testClassifyImageExtensions() {
        for ext in ["jpg", "PNG", "heic", "cr2", "psd"] {
            let url = URL(fileURLWithPath: "/tmp/photo.\(ext)")
            XCTAssertEqual(classify(url), .image, "\(ext) should classify as image")
        }
    }

    func testClassifyOther() {
        for ext in ["txt", "pdf", "", "xml", "json"] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            XCTAssertEqual(classify(url), .other, "\(ext) should classify as other")
        }
    }

    func testClassifyIsCaseInsensitive() {
        XCTAssertEqual(classify(URL(fileURLWithPath: "/a/B.MP4")), .video)
        XCTAssertEqual(classify(URL(fileURLWithPath: "/a/B.Mp3")), .audio)
    }

    // MARK: - Duration Formatting

    func testFormatDurationUnderAnHour() {
        XCTAssertEqual(formatDuration(0), "00:00")
        XCTAssertEqual(formatDuration(5), "00:05")
        XCTAssertEqual(formatDuration(65), "01:05")
        XCTAssertEqual(formatDuration(599), "09:59")
    }

    func testFormatDurationOverAnHour() {
        XCTAssertEqual(formatDuration(3600), "1:00:00")
        XCTAssertEqual(formatDuration(3661), "1:01:01")
        XCTAssertEqual(formatDuration(7325), "2:02:05")
    }

    func testFormatDurationRounds() {
        XCTAssertEqual(formatDuration(59.4), "00:59")
        XCTAssertEqual(formatDuration(59.6), "01:00")
    }

    // MARK: - ScanResults

    func testTotalsAndDuration() {
        var r = ScanResults()
        r.videoCount = 3
        r.audioCount = 2
        r.imageCount = 4
        r.otherCount = 1
        r.videoDuration = 120
        r.audioDuration = 60

        XCTAssertEqual(r.totalFiles, 10)
        XCTAssertEqual(r.totalDuration, 180)
    }

    func testPlainTextSummaryContainsCounts() {
        var r = ScanResults()
        r.videoCount = 2
        r.videoDuration = 90
        r.audioCount = 1
        r.audioDuration = 30
        r.videoUnknown = 1

        let summary = r.plainTextSummary
        XCTAssertTrue(summary.contains("Total duration: 02:00"))
        XCTAssertTrue(summary.contains("Video:  2 files — 01:30"))
        XCTAssertTrue(summary.contains("(1 unknown)"))
        XCTAssertTrue(summary.contains("Audio:  1 file — 00:30"))
    }

    // MARK: - File Collection

    func testCollectFilesNonRecursive() throws {
        let root = try makeTempTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let files = collectFiles(from: [root], recursive: false)
        let names = Set(files.map { $0.lastPathComponent })

        XCTAssertTrue(names.contains("top.mp4"))
        XCTAssertFalse(names.contains("nested.mov"), "non-recursive should skip subdirectories")
    }

    func testCollectFilesRecursive() throws {
        let root = try makeTempTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let files = collectFiles(from: [root], recursive: true)
        let names = Set(files.map { $0.lastPathComponent })

        XCTAssertTrue(names.contains("top.mp4"))
        XCTAssertTrue(names.contains("nested.mov"))
    }

    func testCollectFilesAcceptsIndividualFiles() throws {
        let root = try makeTempTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("top.mp4")
        let files = collectFiles(from: [file], recursive: true)
        XCTAssertEqual(files.map { $0.lastPathComponent }, ["top.mp4"])
    }

    /// Builds a temp directory:  root/top.mp4  +  root/sub/nested.mov
    private func makeTempTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("fc-test-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("sub")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("top.mp4"))
        try Data().write(to: sub.appendingPathComponent("nested.mov"))
        return root
    }
}
