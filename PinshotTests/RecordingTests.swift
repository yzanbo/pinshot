import AVFoundation
import ImageIO
import XCTest

/// 画面の録画の決まり
final class RecordingRulesTests: XCTestCase {
    func testPixelSizeIsEven() {
        // H.264 は偶数でないと書けない
        XCTAssertTrue(RecordingRules.pixelSize(points: CGSize(width: 100.5, height: 51), scale: 1) == (100, 50))
        XCTAssertTrue(RecordingRules.pixelSize(points: CGSize(width: 333, height: 201), scale: 2) == (666, 402))
        XCTAssertTrue(RecordingRules.pixelSize(points: CGSize(width: 0.4, height: 1), scale: 1) == (2, 2))
    }

    func testLocalRectFlipsToTopLeft() {
        // 画面（x 1440〜、高さ 900）の下から 100pt・高さ 200pt の範囲は、上から 600pt
        let screen = CGRect(x: 1440, y: 0, width: 1920, height: 900)
        let rect = CGRect(x: 1500, y: 100, width: 300, height: 200)
        XCTAssertEqual(RecordingRules.localRect(rect, inScreenFrame: screen), CGRect(x: 60, y: 600, width: 300, height: 200))
    }

    func testElapsedText() {
        XCTAssertEqual(RecordingRules.elapsedText(7.9), "0:07")
        XCTAssertEqual(RecordingRules.elapsedText(750), "12:30")
        XCTAssertEqual(RecordingRules.elapsedText(-3), "0:00")
    }

    func testFileName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15, minute: 40, second: 12))!
        XCTAssertEqual(RecordingRules.fileName(for: date, extension: "mp4"), "Pinshot 録画 2026-11-20 15.40.12.mp4")
    }

    func testGIFFramesStayUnderLimit() {
        XCTAssertEqual(RecordingRules.gifFramesPerSecond(duration: 30), 10)
        // 2 分なら 600 コマに収めるため 5 コマ、長くても 2 コマより下げない
        XCTAssertEqual(RecordingRules.gifFramesPerSecond(duration: 120), 5)
        XCTAssertEqual(RecordingRules.gifFramesPerSecond(duration: 600), 2)
        XCTAssertEqual(RecordingRules.gifFrameTimes(duration: 1, framesPerSecond: 4), [0, 0.25, 0.5, 0.75])
        XCTAssertEqual(RecordingRules.gifFrameTimes(duration: 0, framesPerSecond: 4), [0])
    }

    func testGIFSizeFitsLongestSide() {
        // 長い辺を 800 に収める（元より大きくはしない）
        XCTAssertEqual(CGSize(width: 1600, height: 900).fittingLongestSide(RecordingRules.gifMaxSide), CGSize(width: 800, height: 450))
        XCTAssertEqual(CGSize(width: 400, height: 300).fittingLongestSide(RecordingRules.gifMaxSide), CGSize(width: 400, height: 300))
    }

    func testExpiredKeepsNewest() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let files = (0..<5).map { (url: URL(fileURLWithPath: "/tmp/\($0).mp4"), date: base.addingTimeInterval(Double($0))) }
        XCTAssertEqual(RecordingRules.expired(files, now: base, period: nil, keep: 3).map(\.lastPathComponent).sorted(), ["0.mp4", "1.mp4"])
    }

    func testExpiredRemovesOldOnesWithoutCountingThem() {
        // 2 日前のものは期間（1 日）を過ぎたので削除し、数には数えない
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let files = [
            (url: URL(fileURLWithPath: "/tmp/new.mp4"), date: now.addingTimeInterval(-60)),
            (url: URL(fileURLWithPath: "/tmp/old.mp4"), date: now.addingTimeInterval(-2 * 86_400)),
        ]
        XCTAssertEqual(RecordingRules.expired(files, now: now, period: 86_400, keep: 1).map(\.lastPathComponent), ["old.mp4"])
    }

    func testSummaryAndKinds() {
        XCTAssertEqual(RecordingRules.summaryText(count: 0, bytes: 0), "なし")
        XCTAssertTrue(RecordingRules.summaryText(count: 3, bytes: 5_000_000).hasPrefix("3 本・"))
        XCTAssertEqual(ExportKind.allCases.map(\.fileExtension), ["png", "gif", "mp4"])
        XCTAssertEqual(RecordingLimit.twenty.label, "20 本")
    }
}

/// 録画（MP4）から GIF を作る
final class GIFExporterTests: XCTestCase {
    /// テスト用に、色が変わっていく短い MP4 を作る
    private func makeVideo(seconds: Int, fps: Int32, size: CGSize) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixel = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), Int32(frame * 8 % 255), CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            adaptor.append(pixel, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    func testExportsLoopingGIFWithFrames() async throws {
        let video = try await makeVideo(seconds: 2, fps: 10, size: CGSize(width: 64, height: 48))
        let gif = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gif")
        defer {
            try? FileManager.default.removeItem(at: video)
            try? FileManager.default.removeItem(at: gif)
        }
        try await GIFExporter.export(videoAt: video, to: gif) { _ in }
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL, nil))
        // 2 秒 × 10 コマ
        XCTAssertEqual(CGImageSourceGetCount(source), 20)
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gifProperties?[kCGImagePropertyGIFLoopCount] as? Int, 0, "くり返し再生する")
        let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(first.width, 64)
    }
}

/// 保存したものを置く場所（保存先の中を、種類ごと・月ごとに分ける）
final class SaveLocationTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/Users/me/Desktop", isDirectory: true)
    private var date: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func testNotSeparatedUsesBase() {
        // 初期設定は分けない（保存先にそのまま置く）
        for kind in ExportKind.allCases {
            XCTAssertEqual(SaveLocation.folder(base: base, kind: kind, byKind: false, byMonth: false, date: date, calendar: calendar).path, "/Users/me/Desktop")
        }
    }

    func testSeparatedByKind() {
        let paths = ExportKind.allCases.map { SaveLocation.folder(base: base, kind: $0, byKind: true, byMonth: false, date: date, calendar: calendar).path }
        XCTAssertEqual(paths, ["/Users/me/Desktop/画像", "/Users/me/Desktop/GIF", "/Users/me/Desktop/動画"])
    }

    func testSeparatedByKindAndMonth() {
        // 種類の中を、月ごとに分ける（月は 2 けた。並べたとき古い順）
        XCTAssertEqual(SaveLocation.folder(base: base, kind: .movie, byKind: true, byMonth: true, date: date, calendar: calendar).path, "/Users/me/Desktop/動画/2026-03")
        XCTAssertEqual(SaveLocation.folder(base: base, kind: .image, byKind: false, byMonth: true, date: date, calendar: calendar).path, "/Users/me/Desktop/2026-03")
    }
}
