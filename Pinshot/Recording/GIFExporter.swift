import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// 録画（MP4）から GIF を作る。コマの数と大きさは、重くなりすぎないよう抑える（RecordingRules）
enum GIFExporter {
    /// progress には 0〜1 を渡す（裏で呼ぶ）
    static func export(videoAt videoURL: URL, to outputURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.noVideo }
        let naturalSize = try await track.load(.naturalSize)

        let framesPerSecond = RecordingRules.gifFramesPerSecond(duration: duration)
        let times = RecordingRules.gifFrameTimes(duration: duration, framesPerSecond: framesPerSecond)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = naturalSize.fittingLongestSide(RecordingRules.gifMaxSide)
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
