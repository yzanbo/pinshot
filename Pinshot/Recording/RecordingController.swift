import AppKit
import ScreenCaptureKit
import SwiftUI

/// 画面の録画を始める・止める入口（同時に 1 つだけ）。
/// 録画中は、範囲の外側に赤い点線の枠と、近くに操作パネル（経過時間・停止・やめる）を出す（どちらも録画には写さない）。
/// 止めたら、録画を浮かせて再生する（RecordingPlayer）
@MainActor
final class RecordingController {
    static let shared = RecordingController()

    /// 録画を始めた・止めたとき（メニューバーのアイコンを変える）
    var onStateChange: ((Bool) -> Void)?

    private var recorder: ScreenRecorder?
    private var screen: NSScreen?
    private var rect: NSRect = .zero
    private var border: NSWindow?
    private var panel: NSPanel?
    private let model = RecordingPanelModel()
    private var startedAt: Date?
    private var ticker: Timer?
    /// 始めてから止めるまで（準備の間も含む）
    private var isActive = false {
        didSet { if isActive != oldValue { onStateChange?(isActive) } }
    }
    private var isStopping = false

    var isRecording: Bool { isActive }

    /// rect（スクリーン座標）の録画を始める。画面をまたぐときは、screen の中だけにする
    func start(screen: NSScreen, rect: NSRect) {
        guard !isActive else { return }
        let rect = rect.intersection(screen.frame).integral
        guard rect.width >= 8, rect.height >= 8 else { return }
        isActive = true
        isStopping = false
        self.screen = screen
        self.rect = rect
        model.elapsed = 0
        model.isReady = false
        model.stop = { [weak self] in self?.stop() }
        model.cancel = { [weak self] in self?.cancel() }
        showBorder()
        showPanel()

        Task { @MainActor in
            do {
                // 枠と操作パネルは写さない（浮かせた画像などは写す）
                let content = try await ScreenCapturer.shareableContent()
                guard let display = content.display(for: screen) else { throw ScreenRecorder.RecorderError.cannotWrite }
                let mine = Set([border, panel].compactMap { $0.map { CGWindowID($0.windowNumber) } })
                let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { mine.contains($0.windowID) })
                let size = RecordingRules.pixelSize(points: rect.size, scale: screen.backingScaleFactor)
                let recorder = try ScreenRecorder(
                    filter: filter,
                    sourceRect: RecordingRules.localRect(rect, inScreenFrame: screen.frame),
                    pixelWidth: size.width,
                    pixelHeight: size.height,
                    url: try RecordingStore.shared.newURL()
                )
                // 録画は 1 つだけ（shared）なので、止まった知らせはそのまま返す
                recorder.onError = { error in
                    Task { @MainActor in RecordingController.shared.fail(error) }
                }
                // 準備している間に止めた・やめたとき
                guard isActive, !isStopping else { return }
                self.recorder = recorder
                try await recorder.start()
                startedAt = Date()
                model.isReady = true
                startTicker()
            } catch {
                fail(error)
            }
        }
    }

    /// 止めて、録画を浮かせる
    func stop() {
        guard isActive, !isStopping else { return }
        isStopping = true
        guard let recorder else {
            // まだ録画が始まっていない
            finish()
            return
        }
        let rect = rect
        let screen = screen
        finish()
        Task { @MainActor in
            do {
                let url = try await recorder.stop()
                RecordingStore.shared.didAdd()
                RecordingPlayer.show(url: url, pointSize: rect.size, around: rect, on: screen)
            } catch {
                AppAlert.inform("録画を保存できませんでした", detail: error.localizedDescription)
            }
        }
    }

    /// 止めて、録画を捨てる
    func cancel() {
        guard isActive else { return }
        isStopping = true
        let recorder = recorder
        finish()
        Task { await recorder?.cancel() }
    }

    private func fail(_ error: Error) {
        // 止めたあとに届いた知らせは、気にしない
        guard isActive else { return }
        let recorder = recorder
        finish()
        Task { await recorder?.cancel() }
        if ScreenPermission.isPermissionError(error) {
            WelcomeWindowController.shared.show()
        } else {
            AppAlert.inform("録画できませんでした", detail: error.localizedDescription)
        }
    }

    /// 枠と操作パネルを片付けて、録画していない状態に戻す
    private func finish() {
        ticker?.invalidate()
        ticker = nil
        border?.orderOut(nil)
        border = nil
        panel?.orderOut(nil)
        panel = nil
        recorder = nil
        startedAt = nil
        isActive = false
    }

    /// 経過時間を出し、上限に来たら止める
    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let startedAt = self.startedAt else { return }
                let elapsed = Date().timeIntervalSince(startedAt)
                self.model.elapsed = elapsed
                if elapsed >= RecordingRules.maxDuration { self.stop() }
            }
        }
    }

    // MARK: - 枠と操作パネル

    /// 録画している範囲を、外側の赤い点線で示す（範囲の内側には描かないので写らない）
    private func showBorder() {
        border = CaptureOutline.show(around: rect, color: .systemRed)
    }

    /// 操作パネルを、枠の下 → 上 → 枠の中の下の順に、画面に収まる場所へ置く（ドラッグで動かせる）
    private func showPanel() {
        guard let screen else { return }
        let hosting = FirstMouseHostingView(rootView: RecordingPanelView(model: model))
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let gap: CGFloat = 12
        let candidates = [
            NSPoint(x: rect.midX - size.width / 2, y: rect.minY - gap - size.height),
            NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + gap),
            NSPoint(x: rect.midX - size.width / 2, y: rect.minY + gap),
        ]
        let origin = ScreenGeometry.firstFittingOrigin(candidates, size: size, in: visible)

        let panel = OverlayPanel(contentRect: NSRect(origin: origin, size: size), level: .statusBar)
        panel.isMovableByWindowBackground = true
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

/// 録画中の操作パネルの状態
@MainActor
final class RecordingPanelModel: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    /// 録画が始まったか（準備している間は「準備しています…」）
    @Published var isReady = false
    var stop: () -> Void = {}
    var cancel: () -> Void = {}
}

/// 録画中の操作パネル（● 経過時間・停止・やめる）
private struct RecordingPanelView: View {
    @ObservedObject var model: RecordingPanelModel

    private var remaining: TimeInterval { RecordingRules.maxDuration - model.elapsed }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(model.isReady ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isReady ? RecordingRules.elapsedText(model.elapsed) : "準備しています…")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                // 上限の 1 分前から、残りの時間を出す
                if model.isReady, remaining <= 60 {
                    Text("あと \(RecordingRules.elapsedText(remaining)) で止まります")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(minWidth: 64, alignment: .leading)
            Button(action: model.stop) {
                Label("停止", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color.red))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("録画を止めて、浮かせて再生する（メニューバー・ショートカットでも止められる）")
            .hoverRole()
            Button("やめる", action: model.cancel)
                .controlSize(.small)
                .help("録画を止めて、捨てる")
                .hoverRole()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
        .fixedSize()
    }
}
