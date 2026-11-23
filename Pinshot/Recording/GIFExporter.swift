import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// 録画（MP4）から GIF を作る。コマの数と大きさは、重くなりすぎないよう抑える（RecordingRules・GIFSettings）
enum GIFExporter {
    /// settings の作り方で作る。progress には 0〜1 を渡す（裏で呼ぶ）
    static func export(
        videoAt videoURL: URL,
        to outputURL: URL,
        settings: GIFSettings = .standard,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.noVideo }
        let naturalSize = try await track.load(.naturalSize)

        let framesPerSecond = settings.framesPerSecond(duration: duration)
        let times = RecordingRules.gifFrameTimes(duration: duration, framesPerSecond: framesPerSecond)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = naturalSize.fittingLongestSide(settings.maxSide)
        // 決めた時刻のコマを、なるべくそのまま取る
        let tolerance = CMTime(seconds: 0.5 / framesPerSecond, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
            throw ExportError.cannotWrite
        }
        // くり返し再生する
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / framesPerSecond],
        ] as CFDictionary

        for (index, time) in times.enumerated() {
            try Task.checkCancellation()
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            CGImageDestinationAddImage(destination, image, frameProperties)
            progress(Double(index + 1) / Double(times.count))
        }
        guard CGImageDestinationFinalize(destination) else { throw ExportError.cannotWrite }
    }

    /// settings の作り方で、一時フォルダに GIF を作り、その場所を返す（使い終わったら、呼ぶ側が消す。
    /// 作れなかったときは、ここで消してから投げる）。progress には 0〜1 を渡す（画面の側で呼ぶ）
    static func exportToTemporaryFile(
        videoAt videoURL: URL,
        settings: GIFSettings = .standard,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> URL {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gif")
        do {
            try await export(videoAt: videoURL, to: temporary, settings: settings) { value in
                Task { @MainActor in progress(value) }
            }
            return temporary
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// 録画の最初のコマ（上げたものの一覧に出す縮小画像など。取れなければ nil）
    static func firstFrame(of videoURL: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        return try? await generator.image(at: .zero).image
    }

    enum ExportError: LocalizedError {
        case noVideo
        case cannotWrite

        var errorDescription: String? {
            switch self {
            case .noVideo: "録画を読めませんでした"
            case .cannotWrite: "GIF を書けませんでした"
            }
        }
    }
}
