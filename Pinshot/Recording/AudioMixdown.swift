import AVFoundation

/// 録画の音の形（AAC・48 kHz）。録画（ScreenRecorder）と、音を混ぜる処理（AudioMixdown）で同じものを使う
enum RecordingAudioFormat {
    static let sampleRate = 48_000

    /// AAC で書くときの設定（channels: 1 ならモノラル、2 ならステレオ）
    static func aacSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 1 ? 96_000 : 128_000,
        ]
    }

    /// 圧縮しない形（32 ビットの浮動小数点。マイクから受け取る・混ぜるときに読み出す）
    static func pcmSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
    }

    /// 混ぜるときに読み出す形（ステレオ）
    static let mixingPCMSettings = pcmSettings(channels: 2)
}

/// 音の線が何本かある動画を、映像はそのまま（作り直さない）、音を 1 本に混ぜて書き直す。
/// Mac の音とマイクを両方録ると、録っている間は別々の線に書くため、止めたあとにこれで 1 本にする
/// （線が 2 本のままだと、ブラウザ・Slack などでは片方しか鳴らないことが多いため）
enum AudioMixdown {
    enum MixdownError: LocalizedError {
        case cannotRead
        case cannotWrite

        var errorDescription: String? {
            switch self {
            case .cannotRead: "録画の音を読めませんでした"
            case .cannotWrite: "録画の音を混ぜて書けませんでした"
            }
        }
    }

    /// source を読み、映像はそのまま、中身のある音の線をすべて 1 本に混ぜて destination（MP4）に書く。
    /// 長さは source と同じにする（最後のコマを、元の動画の終わりまで出したままにする）
    static func mix(_ source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        // 1 つも音が届かなかった線は、混ぜない（読めずに失敗するため）
        var audioTracks: [AVAssetTrack] = []
        for track in try await asset.loadTracks(withMediaType: .audio) {
            let range = try await track.load(.timeRange)
            if range.duration.isNumeric, range.duration > .zero { audioTracks.append(track) }
        }

        let reader = try AVAssetReader(asset: asset)
        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        // 共有したときに、読み込みながら再生できるように（目次をファイルの頭に置く）
        writer.shouldOptimizeForNetworkUse = true
        var pairs: [(output: AVAssetReaderOutput, input: AVAssetWriterInput)] = []

        if let video = videoTracks.first {
            // 映像は作り直さず、そのまま写す
            let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            let format = try await video.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
            input.transform = try await video.load(.preferredTransform)
            pairs.append((output, input))
        }
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: RecordingAudioFormat.mixingPCMSettings)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: RecordingAudioFormat.aacSettings(channels: 2))
            pairs.append((output, input))
        }
        for pair in pairs {
            guard reader.canAdd(pair.output) else { throw MixdownError.cannotRead }
            reader.add(pair.output)
            guard writer.canAdd(pair.input) else { throw MixdownError.cannotWrite }
            writer.add(pair.input)
        }

        guard reader.startReading() else { throw reader.error ?? MixdownError.cannotRead }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? MixdownError.cannotWrite
        }
        writer.startSession(atSourceTime: .zero)
        // 映像と音を、それぞれの列で同時に写す（片方ずつだと、書く側が交互に並べようとして止まるため）
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for (index, pair) in pairs.enumerated() {
                group.enter()
                copy(pair.output, into: pair.input, on: DispatchQueue(label: "Pinshot.AudioMixdown.\(index)")) { group.leave() }
            }
            group.notify(queue: .global()) { continuation.resume() }
        }
        if reader.status == .failed || writer.status == .failed {
            let error = reader.error ?? writer.error ?? MixdownError.cannotWrite
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw writer.error ?? MixdownError.cannotWrite
        }
    }

    /// output から読んだものを、すべて input に書く（queue の上で。読み終えた・書けなくなったら completion を呼ぶ）
    private static func copy(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, on queue: DispatchQueue, completion: @escaping () -> Void) {
        var finished = false
        /// 終える（読み終えたときだけ、書き終えたと知らせる。書けなくなったときは、書く側がもう止まっている）
        func finish(markingAsFinished: Bool) {
            finished = true
            if markingAsFinished { input.markAsFinished() }
            completion()
        }
        input.requestMediaDataWhenReady(on: queue) {
            guard !finished else { return }
            while input.isReadyForMoreMediaData {
                guard let buffer = output.copyNextSampleBuffer() else { return finish(markingAsFinished: true) }
                guard input.append(buffer) else { return finish(markingAsFinished: false) }
            }
        }
    }
}
