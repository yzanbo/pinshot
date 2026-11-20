import AppKit
import ScreenCaptureKit

/// 「画面を撮る → 撮るものを選ぶ →（タイマー）→ 画像を浮かせる」の流れをまとめる
@MainActor
final class CaptureController {
    private var selection: SelectionController?
    private var isCapturing = false

    /// 範囲選択の画面を出してキャプチャを始める
    func start(mode: CaptureMode = .region, timer: Int = 0) {
        // 録画の間は、範囲を選ぶ画面まで録画に写ってしまうので、撮らない
        guard !isCapturing, !RecordingController.shared.isRecording else {
            if RecordingController.shared.isRecording { NSSound.beep() }
            return
        }
        isCapturing = true
        let windows = WindowList.visibleWindows()

        // 押した瞬間に、すべての画面に透明なウィンドウをかぶせる（そのまま範囲を選ぶ画面になる。カーソルは準備ができてから変える）
        let shield = CaptureShield()
        shield.show()

        Task { @MainActor [weak self] in
            // 撮れなかったときは、かぶせたウィンドウを外す（範囲を選ぶ画面に渡したものは、そちらが閉じる）
            defer { shield.close() }
            guard let self else { return }
            do {
                let content = try await ScreenCapturer.shareableContent()
                let shots = try await ScreenCapturer.captureAllScreens(content: content, excluding: shield.windowIDs)
                guard !shots.isEmpty else {
                    isCapturing = false
                    return
                }
                let options = CaptureOptions(mode: mode, timer: timer)
                let selection = SelectionController(
                    shots: shots,
                    windows: windows,
                    options: options,
                    existingWindows: shield.handOver()
                ) { [weak self] target in
                    guard let self else { return }
                    self.selection = nil
                    guard let target else {
                        self.isCapturing = false
                        return
                    }
                    Task { @MainActor in
                        await self.capture(target, shots: shots, timer: options.timer)
                        self.isCapturing = false
                    }
                }
                self.selection = selection
                // 撮った画面を先に映し切ってから、開いていたメニューを閉じ、範囲を選べる状態にする。
                // 順番が逆だと、メニュー（ツールバーの ▾・ほかのアプリのメニューバーのメニュー）が一瞬消えて、また出たように見える
                selection.presentScreens()
                try? await Task.sleep(for: .milliseconds(30))
                if OpenMenus.isAnyOpen {
                    // 開いたままだと、macOS がメニューの操作だけを受け付けるので、範囲を選べない
                    OpenMenus.closeAll()
                    try? await Task.sleep(for: .milliseconds(30))
                }
                selection.begin()
            } catch {
                isCapturing = false
                handle(error)
            }
        }
    }

    /// 一覧から選んだウィンドウを、範囲選択の画面を出さずに撮る
    func captureWindow(id: CGWindowID) {
        guard !isCapturing, !RecordingController.shared.isRecording else { return }
        guard let info = WindowList.visibleWindows().first(where: { $0.id == id }) else {
            NSSound.beep()
            return
        }
        isCapturing = true
        Task { @MainActor in
            await capture(.window(info), shots: [], timer: 0)
            isCapturing = false
        }
    }

    // MARK: - 撮る

    private func capture(_ target: CaptureTarget, shots: [ScreenShot], timer: Int) async {
        do {
            if timer > 0 {
                await CountdownPanel.run(seconds: timer, on: screen(of: target))
            }
            // タイマーを使ったときは、待ったあとの画面を撮り直す（使わないときは、範囲を選ぶ前に撮った画面を使う）。
            // 画面に出ているものの一覧（shareableContent）は、撮り直すときだけ取る（撮ってある画面を使うときは待たない）
            switch target {
            case .region(let screen, let rect):
                guard let shot = try await shot(of: screen, shots: shots, fresh: timer > 0),
                      let cropped = ScreenCapturer.crop(shot, to: rect) else { return }
                PinManager.shared.pin(image: cropped.image, imageSize: cropped.size, frame: rect)

            case .window(let info):
                let content = try await ScreenCapturer.shareableContent()
                if let captured = try await ScreenCapturer.captureWindow(id: info.id, content: content) {
                    let frame = NSRect(origin: info.frame.origin, size: captured.size)
                    PinManager.shared.pin(image: captured.image, imageSize: captured.size, frame: frame)
                } else if let screen = ScreenGeometry.screen(intersecting: info.frame, orMain: false),
                          let shot = try await shot(of: screen, shots: shots, fresh: true, content: content),
                          let cropped = ScreenCapturer.crop(shot, to: info.frame) {
                    // ウィンドウだけを撮れなかったときは、画面から切り抜く
                    PinManager.shared.pin(image: cropped.image, imageSize: cropped.size, frame: info.frame)
                }

            case .record(let screen, let rect):
                // 録画を始める（止めたら浮かせて再生する）
                RecordingController.shared.start(screen: screen, rect: rect)

            case .screen(let screen):
                guard let shot = try await shot(of: screen, shots: shots, fresh: timer > 0) else { return }
                // 画面全体は大きいので、半分の大きさで画面の真ん中に浮かせる
                let size = screen.frame.size
                let zoom: CGFloat = 0.5
                let frame = NSRect(
                    x: screen.frame.midX - size.width * zoom / 2,
                    y: screen.frame.midY - size.height * zoom / 2,
                    width: size.width * zoom,
                    height: size.height * zoom
                )
                PinManager.shared.pin(image: shot.image, imageSize: size, frame: frame, zoom: zoom)
            }
        } catch {
            handle(error)
        }
    }

    /// screen の画面。fresh でなければ、範囲を選ぶ前に撮った画面を使う。撮り直すときは content（なければ取り直す）で撮る
    private func shot(of screen: NSScreen, shots: [ScreenShot], fresh: Bool, content: SCShareableContent? = nil) async throws -> ScreenShot? {
        if !fresh, let shot = shots.first(where: { $0.screen == screen }) {
            return shot
        }
        let current: SCShareableContent
        if let content {
            current = content
        } else {
            current = try await ScreenCapturer.shareableContent()
        }
        return try await ScreenCapturer.capture(screen: screen, content: current)
    }

    private func screen(of target: CaptureTarget) -> NSScreen? {
        switch target {
        case .region(let screen, _), .screen(let screen), .record(let screen, _):
            return screen
        case .window(let info):
            return ScreenGeometry.screen(intersecting: info.frame, orMain: false)
        }
    }

    private func handle(_ error: Error) {
        if ScreenPermission.isPermissionError(error) {
            WelcomeWindowController.shared.show()
            return
        }
        AppAlert.inform("キャプチャできませんでした", detail: error.localizedDescription)
    }
}
