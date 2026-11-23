import AVFoundation
import ScreenCaptureKit

/// 画面の一部を録画して、MP4（H.264。音を録るときは AAC も）に書く。
/// ScreenCaptureKit の SCStream で画面（と Mac の音）を受け取り、AVAssetWriter で書く（macOS 14 でも使えるように、SCRecordingOutput は使わない）。
/// マイクの音は MicrophoneCapture で受け取る。Mac の音とマイクを両方録るときは、別々の線に書いておき、止めたあとに 1 本に混ぜる（AudioMixdown）
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url: URL
    /// 録画が途中で止まったとき（画面がなくなった・許可を外したなど）
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    /// Mac の音・マイクの音を書く線（録らないときは nil）
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private var microphone: MicrophoneCapture?
    /// 書いている途中のファイル（音を混ぜるときは一時ファイル。混ぜないときは url）
    private let workURL: URL
    /// 届いたコマ・音を書く順番待ちの列（コマ・音はこの列で受け取り、書く）
    private let queue = DispatchQueue(label: "Pinshot.ScreenRecorder")
    /// 最初のコマを書いたか（書き始めの時刻は、最初のコマの時刻にする。音はそれより後のものだけを書く）
    private var hasStartedSession = false
    private var sessionStart: CMTime = .invalid
    /// 最後に書いたコマ（止めたときに、止めた時刻の少し前にもう一度書く）
    private var lastFrame: CMSampleBuffer?
    /// 止め始めたら、もうコマを書かない
    private var isStopping = false

    /// filter: 写すもの。sourceRect: 画面の左上を原点にした、録画する範囲（ポイント）。
    /// pixelWidth・pixelHeight: 録画の大きさ（偶数）。audio: 入れる音（マイクの許可は、呼ぶ前に確かめておく）
    init(filter: SCContentFilter, sourceRect: CGRect, pixelWidth: Int, pixelHeight: Int, audio: RecordingAudio, url: URL) throws {
        self.url = url
        // 両方の音を録るときは、一時ファイルに書いてから、音を混ぜて url に書く
        workURL = audio == .systemAndMicrophone
            ? FileManager.default.temporaryDirectory.appendingPathComponent("Pinshot-recording-\(UUID().uuidString).mp4")
            : url
        writer = try AVAssetWriter(outputURL: workURL, fileType: .mp4)
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
        // Mac の音はステレオ、マイクはモノラルで書く
        systemAudioInput = audio.capturesSystemAudio ? AVAssetWriterInput(mediaType: .audio, outputSettings: RecordingAudioFormat.aacSettings(channels: 2)) : nil
        microphoneInput = audio.capturesMicrophone ? AVAssetWriterInput(mediaType: .audio, outputSettings: RecordingAudioFormat.aacSettings(channels: 1)) : nil
        for audioInput in [systemAudioInput, microphoneInput].compactMap({ $0 }) {
            audioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(audioInput) else { throw RecorderError.cannotWrite }
            writer.add(audioInput)
        }
        super.init()

        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: RecordingRules.framesPerSecond)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 6
        if audio.capturesSystemAudio {
            config.capturesAudio = true
            config.sampleRate = RecordingAudioFormat.sampleRate
            config.channelCount = 2
            // Pinshot 自身の音（エラーのときの音・浮かせた録画の音など）は入れない
            config.excludesCurrentProcessAudio = true
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if audio.capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        self.stream = stream
        if audio.capturesMicrophone {
            microphone = try MicrophoneCapture(queue: queue) { [weak self] buffer in
                guard let self else { return }
                self.appendAudio(buffer, to: self.microphoneInput)
            }
        }
    }

    func start() async throws {
        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotWrite }
        // マイクを先に動かしておく（画面の最初のコマから、声が入るように）
        microphone?.start()
        do {
            try await stream?.startCapture()
        } catch {
            microphone?.stop()
            throw error
        }
    }

    /// 止めて、書き終えたファイルを返す。最後のコマは、止めた時刻まで表示したままにする
    /// （画面が動かないとコマが届かないため。音を録っていると、終わりの時刻を決めるだけでは映像が伸びないので、最後のコマをもう一度書く）
    func stop() async throws -> URL {
        let stopTime = CMClockGetTime(CMClockGetHostTimeClock())
        try? await stream?.stopCapture()
        stream = nil
        microphone?.stop()
        microphone = nil
        let (started, last) = queue.sync { () -> (Bool, CMSampleBuffer?) in
            isStopping = true
            return (hasStartedSession, lastFrame)
        }
        guard started else {
            // 1 コマも届かなかった
            writer.cancelWriting()
            removeFiles()
            throw RecorderError.noFrames
        }
        if let last, let held = Self.frame(last, heldUntil: stopTime), input.isReadyForMoreMediaData {
            input.append(held)
        }
        input.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        writer.endSession(atSourceTime: stopTime)
        await writer.finishWriting()
        if writer.status == .failed {
            removeFiles()
            throw writer.error ?? RecorderError.cannotWrite
        }
        if workURL != url {
            // Mac の音とマイクの音を、1 本の音に混ぜる。混ぜられなかったときは、録画を失わないよう、線が 2 本のままのものを残す
            do {
                try await AudioMixdown.mix(workURL, to: url)
                try? FileManager.default.removeItem(at: workURL)
            } catch {
                NSLog("Pinshot: 録画の音を 1 本に混ぜられませんでした: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: workURL, to: url)
            }
        }
        return url
    }

    /// 止めて、書きかけのファイルを捨てる
    func cancel() async {
        try? await stream?.stopCapture()
        stream = nil
        microphone?.stop()
        microphone = nil
        queue.sync { isStopping = true }
        writer.cancelWriting()
        removeFiles()
    }

    /// 書きかけ・書き終えたファイルを消す
    private func removeFiles() {
        try? FileManager.default.removeItem(at: workURL)
        if workURL != url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - SCStreamOutput・SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen: appendFrame(sampleBuffer)
        case .audio: appendAudio(sampleBuffer, to: systemAudioInput)
        default: break
        }
    }

    /// 画面のコマを書く（最初のコマの時刻から書き始める）
    private func appendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard !isStopping, sampleBuffer.isValid, Self.isComplete(sampleBuffer) else { return }
        if !hasStartedSession {
            sessionStart = sampleBuffer.presentationTimeStamp
            writer.startSession(atSourceTime: sessionStart)
            hasStartedSession = true
        }
        if input.isReadyForMoreMediaData, input.append(sampleBuffer) {
            lastFrame = sampleBuffer
        }
    }

    /// frame を、止めた時刻 stopTime の 1 コマ前に置き直したもの（もう 2 コマ以上前でなければ nil。置き直さなくても、止めた時刻まで届く）
    static func frame(_ frame: CMSampleBuffer, heldUntil stopTime: CMTime) -> CMSampleBuffer? {
        let interval = CMTime(value: 1, timescale: RecordingRules.framesPerSecond)
        let time = stopTime - interval
        guard time > frame.presentationTimeStamp + interval else { return nil }
        let timing = CMSampleTimingInfo(duration: interval, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        return try? CMSampleBuffer(copying: frame, withNewTiming: [timing])
    }

    /// 音を書く（queue の上で呼ぶ）。最初のコマより前の音は書かない（書き始める前は書けないため）
    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to audioInput: AVAssetWriterInput?) {
        guard let audioInput, !isStopping, hasStartedSession, sampleBuffer.isValid,
              sampleBuffer.presentationTimeStamp >= sessionStart,
              audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
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
