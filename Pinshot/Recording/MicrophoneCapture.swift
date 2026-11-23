import AVFoundation

/// マイクの音を受け取る（AVCaptureSession。macOS 14 でも同じ仕組みで録れるよう、ScreenCaptureKit のマイクは使わない）。
/// 届いた音の時刻は、画面のコマと同じ時計（ホストの時計）に直してから渡す（映像と音がずれないように）
final class MicrophoneCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum MicrophoneError: LocalizedError {
        case noDevice
        case cannotUse

        var errorDescription: String? {
            switch self {
            case .noDevice: "マイクが見つかりませんでした"
            case .cannotUse: "マイクを使えませんでした"
            }
        }
    }

    /// 使えるマイクがあるか（Mac mini などで、マイクをつないでいないときは false）
    static var isAvailable: Bool { AVCaptureDevice.default(for: .audio) != nil }

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let onSample: (CMSampleBuffer) -> Void

    /// queue: 届いた音を渡す列（録画のコマを書く列と同じにして、順番に書く）。
    /// 音は 48 kHz・モノラルにそろえて渡す
    init(queue: DispatchQueue, onSample: @escaping (CMSampleBuffer) -> Void) throws {
        guard let device = AVCaptureDevice.default(for: .audio) else { throw MicrophoneError.noDevice }
        self.onSample = onSample
        super.init()
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw MicrophoneError.cannotUse }
        session.addInput(input)
        output.audioSettings = RecordingAudioFormat.pcmSettings(channels: 1)
        guard session.canAddOutput(output) else { throw MicrophoneError.cannotUse }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
    }

    /// 受け取り始める（マイクが動き出すまで待つので、画面を止めない列から呼ぶ）
    func start() {
        session.startRunning()
    }

    func stop() {
        output.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onSample(Self.retimed(sampleBuffer, from: session.synchronizationClock))
    }

    /// buffer の時刻を、clock の時刻からホストの時計の時刻に直す（同じ時計なら、そのまま）
    static func retimed(_ buffer: CMSampleBuffer, from clock: CMClock?) -> CMSampleBuffer {
        let host = CMClockGetHostTimeClock()
        guard let clock, !CFEqual(clock, host) else { return buffer }
        let time = buffer.presentationTimeStamp
        let offset = CMSyncConvertTime(time, from: clock, to: host) - time
        guard offset.isNumeric, offset != .zero, let timings = try? buffer.sampleTimingInfos() else { return buffer }
        let shifted = timings.map { timing -> CMSampleTimingInfo in
            var timing = timing
            timing.presentationTimeStamp = timing.presentationTimeStamp + offset
            if timing.decodeTimeStamp.isNumeric { timing.decodeTimeStamp = timing.decodeTimeStamp + offset }
            return timing
        }
        return (try? CMSampleBuffer(copying: buffer, withNewTiming: shifted)) ?? buffer
    }
}
