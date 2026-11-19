import AppKit
import ScreenCaptureKit

/// 「画面を撮る → 撮るものを選ぶ →（タイマー）→ 画像を浮かせる」の流れをまとめる
@MainActor
final class CaptureController {
    private var selection: SelectionController?
    private var isCapturing = false

    /// スクロールキャプチャ：撮るウィンドウをクリックで選んでもらう（マウスを乗せると、撮るスクロール領域を枠で示す）。
    /// ドラッグで範囲を選ぶこともできる
    func startScrollCapture() {
        guard !ScrollCaptureController.shared.isRunning else { return }
        start(mode: .scroll)
    }

    /// 範囲選択の画面を出してキャプチャを始める
    func start(mode: CaptureMode = .region, timer: Int = 0) {
        guard !isCapturing else { return }
        isCapturing = true
        let windows = WindowList.visibleWindows()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await ScreenCapturer.shareableContent()
                let shots = try await ScreenCapturer.captureAllScreens(content: content)
                guard !shots.isEmpty else {
                    isCapturing = false
                    return
                }
                let options = CaptureOptions(mode: mode, timer: timer)
                let selection = SelectionController(shots: shots, windows: windows, options: options) { [weak self] target in
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
                selection.begin()
            } catch {
                isCapturing = false
                handle(error)
            }
        }
    }

    /// 一覧から選んだウィンドウを、範囲選択の画面を出さずに撮る
    func captureWindow(id: CGWindowID) {
        guard !isCapturing else { return }
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
            // タイマーを使ったときは、待ったあとの画面を撮り直す
            let content = try await ScreenCapturer.shareableContent()

            switch target {
            case .region(let screen, let rect):
                guard let shot = try await shot(of: screen, shots: shots, fresh: timer > 0, content: content),
                      let cropped = ScreenCapturer.crop(shot, to: rect) else { return }
                PinManager.shared.pin(image: cropped.image, imageSize: cropped.size, frame: rect)

            case .window(let info):
                if let captured = try await ScreenCapturer.captureWindow(id: info.id, content: content) {
                    let frame = NSRect(origin: info.frame.origin, size: captured.size)
                    PinManager.shared.pin(image: captured.image, imageSize: captured.size, frame: frame)
                } else if let screen = ScreenGeometry.screen(intersecting: info.frame, orMain: false),
                          let shot = try await shot(of: screen, shots: shots, fresh: true, content: content),
                          let cropped = ScreenCapturer.crop(shot, to: info.frame) {
                    // ウィンドウだけを撮れなかったときは、画面から切り抜く
                    PinManager.shared.pin(image: cropped.image, imageSize: cropped.size, frame: info.frame)
                }

            case .scroll(let screen, let rect, let window, let point):
                // クリックで選んだときは、そのウィンドウのその場所のスクロール領域を、改めて確かめる
                var area = rect
                if let window, let point,
                   let found = await ScrollTargetFinder.scrollAreaRetrying(at: point, in: window) {
                    area = found
                }
                // 画面をまたぐときは、クリックした画面の中だけにする
                let target = point.flatMap { ScreenGeometry.screen(containing: $0, orMain: false) } ?? screen
                let clipped = area.intersection(target.frame).integral
                guard clipped.width >= 40, clipped.height >= 40 else { return }
                // スクロールしながら撮る（終わったら浮かせる）
                ScrollCaptureController.shared.start(screen: target, rect: clipped, window: window, scrollPoint: point)

            case .screen(let screen):
                guard let shot = try await shot(of: screen, shots: shots, fresh: timer > 0, content: content) else { return }
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

    private func shot(of screen: NSScreen, shots: [ScreenShot], fresh: Bool, content: SCShareableContent) async throws -> ScreenShot? {
        if !fresh, let shot = shots.first(where: { $0.screen == screen }) {
            return shot
        }
        return try await ScreenCapturer.capture(screen: screen, content: content)
    }

    private func screen(of target: CaptureTarget) -> NSScreen? {
        switch target {
        case .region(let screen, _), .screen(let screen), .scroll(let screen, _, _, _):
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
        let alert = NSAlert()
        alert.messageText = "キャプチャできませんでした"
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}
