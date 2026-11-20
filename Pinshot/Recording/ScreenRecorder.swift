import AVFoundation
import ScreenCaptureKit

/// 画面の一部を録画して、MP4（H.264）に書く。
/// ScreenCaptureKit の SCStream で画面を受け取り、AVAssetWriter で書く（macOS 14 でも使えるように、SCRecordingOutput は使わない）
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url: URL
    /// 録画が途中で止まったとき（画面がなくなった・許可を外したなど）
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    /// 届いたコマを書く順番待ちの列（コマはこの列で受け取り、書く）
    private let queue = DispatchQueue(label: "Pinshot.ScreenRecorder")
    /// 最初のコマを書いたか（書き始めの時刻は、最初のコマの時刻にする）
    private var hasStartedSession = false
    /// 止め始めたら、もうコマを書かない
    private var isStopping = false

    /// filter: 写すもの。sourceRect: 画面の左上を原点にした、録画する範囲（ポイント）。
    /// pixelWidth・pixelHeight: 録画の大きさ（偶数）
    init(filter: SCContentFilter, sourceRect: CGRect, pixelWidth: Int, pixelHeight: Int, url: URL) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        // 画面の文字が読める画質にする（大きさとコマ数に合わせたビットレート）
        let bitRate = max(2_000_000, pixelWidth * pixelHeight * Int(RecordingRules.framesPerSecond) / 6)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoMaxKeyFrameIntervalKey: Int(RecordingRules.framesPerSecond) * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw RecorderError.cannotWrite }
        writer.add(input)
        super.init()

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: RecordingRules.framesPerSecond)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 6
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
    }

    func start() async throws {
        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotWrite }
        try await stream?.startCapture()
    }

    /// 止めて、書き終えたファイルを返す。最後のコマは、止めた時刻まで表示したままにする（画面が動かないと、コマが届かないため）
    func stop() async throws -> URL {
        let stopTime = CMClockGetTime(CMClockGetHostTimeClock())
        try? await stream?.stopCapture()
        stream = nil
        let started = queue.sync { () -> Bool in
            isStopping = true
            return hasStartedSession
        }
        guard started else {
            // 1 コマも届かなかった
            writer.cancelWriting()
            throw RecorderError.noFrames
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: stopTime)
        await writer.finishWriting()
        if writer.status == .failed { throw writer.error ?? RecorderError.cannotWrite }
        return url
    }

    /// 止めて、書きかけのファイルを捨てる
    func cancel() async {
        try? await stream?.stopCapture()
        stream = nil
        queue.sync { isStopping = true }
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - SCStreamOutput・SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !isStopping, sampleBuffer.isValid, Self.isComplete(sampleBuffer) else { return }
        if !hasStartedSession {
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            hasStartedSession = true
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }

    /// 中身のあるコマか（画面が動かないときは、中身のない知らせだけが届く）
    private static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    enum RecorderError: LocalizedError {
        case cannotWrite
        case noFrames

        var errorDescription: String? {
            switch self {
            case .cannotWrite: "録画のファイルを書けませんでした"
            case .noFrames: "録画できた画面がありませんでした"
            }
        }
    }
}
