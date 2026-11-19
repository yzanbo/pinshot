import AppKit

/// 浮かせている画像をまとめて持つ
@MainActor
final class PinManager {
    static let shared = PinManager()

    private var pins: [PinController] = []

    /// 閉じた画像（新しい順、最大 10 枚）。「閉じた画像を戻す」で使う
    private var closedPins: [ClosedPin] = []
    private let maxClosedPins = 10

    private struct ClosedPin {
        let image: CGImage
        let imageSize: CGSize
        /// 書き込み・トリミング・背景・最前面の設定
        let state: PinController.RestoreState
        let frame: NSRect
        let zoom: CGFloat
        let opacity: CGFloat
    }

    private init() {
        // ディスプレイをつないだ・外した・並びを変えたときは、画面の外に出た画像を戻す
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PinManager.shared.pins.forEach { $0.ensureOnScreen() }
            }
        }
    }

    var hasClickThroughPins: Bool { pins.contains { $0.isClickThrough } }
    var canRestore: Bool { !closedPins.isEmpty }
    var hasPins: Bool { !pins.isEmpty }
    /// 浮かせている画像の数
    var pinCount: Int { pins.count }

    /// zoom: 最初の倍率（frame はこの倍率をかけた大きさで渡す）
    func pin(image: CGImage, imageSize: CGSize, frame: NSRect, zoom: CGFloat = 1) {
        let controller = makeController(image: image, imageSize: imageSize, frame: frame, zoom: zoom, restoring: nil)
        controller.show()

        if AppSettings.shared.copyAfterCapture {
            ImageExporter.writeToPasteboard(image, pointSize: imageSize)
            controller.canvas.showHUD("コピーしました")
        }
    }

    private func makeController(
        image: CGImage,
        imageSize: CGSize,
        frame: NSRect,
        zoom: CGFloat,
        restoring: PinController.RestoreState?
    ) -> PinController {
        let controller = PinController(image: image, imageSize: imageSize, frame: frame, zoom: zoom, restoring: restoring)
        controller.onClose = { [weak self] closed in
            self?.didClose(closed)
        }
        pins.append(controller)
        return controller
    }

    private func didClose(_ controller: PinController) {
        pins.removeAll { $0 === controller }
        closedPins.insert(ClosedPin(
            image: controller.canvas.baseImage,
            imageSize: controller.canvas.imageSize,
            state: controller.restoreState,
            frame: controller.contentScreenFrame,
            zoom: controller.zoom,
            opacity: controller.panel.alphaValue
        ), at: 0)
        if closedPins.count > maxClosedPins {
            closedPins.removeLast(closedPins.count - maxClosedPins)
        }
    }

    /// 最後に閉じた画像を、書き込みごと元の場所に戻す
    func restoreLastClosed() {
        guard !closedPins.isEmpty else {
            NSSound.beep()
            return
        }
        let closed = closedPins.removeFirst()
        let controller = makeController(
            image: closed.image,
            imageSize: closed.imageSize,
            frame: closed.frame,
            zoom: closed.zoom,
            restoring: closed.state
        )
        controller.setOpacity(closed.opacity)
        controller.show()
        controller.ensureOnScreen()
    }

    /// クリップボードの画像を、マウスのある画面の真ん中に浮かせる。画像がなければ false
    @discardableResult
    func pinClipboardImage() -> Bool {
        guard
            let image = NSImage(pasteboard: .general),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            image.size.width >= 1, image.size.height >= 1
        else { return false }

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = image.size
        // 大きい画像は、画面の 7 割に収まるよう縮める
        let zoom = min(1, visible.width * 0.7 / size.width, visible.height * 0.7 / size.height)
        let frame = NSRect(
            x: visible.midX - size.width * zoom / 2,
            y: visible.midY - size.height * zoom / 2,
            width: size.width * zoom,
            height: size.height * zoom
        )
        pin(image: cgImage, imageSize: size, frame: frame, zoom: zoom)
        return true
    }

    /// スクロールキャプチャの間は、浮かせた画像がスクロール操作を受けないようにする
    func setMouseEventsSuspended(_ suspended: Bool) {
        for pin in pins {
            pin.panel.ignoresMouseEvents = suspended || pin.isClickThrough
        }
    }

    /// スクロールキャプチャの縦長の画像を、撮った範囲の上端から、画面に収まる大きさで浮かせる
    func pinScrollCapture(image: CGImage, pointSize: CGSize, sourceRect: NSRect, screen: NSScreen) {
        let visible = screen.visibleFrame
        let zoom = min(1, visible.height * 0.9 / max(pointSize.height, 1), visible.width * 0.9 / max(pointSize.width, 1))
        let size = NSSize(width: pointSize.width * zoom, height: pointSize.height * zoom)
        let top = min(sourceRect.maxY, visible.maxY)
        var origin = NSPoint(x: sourceRect.minX, y: top - size.height)
        origin.y = max(origin.y, visible.minY)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        pin(image: image, imageSize: pointSize, frame: NSRect(origin: origin, size: size), zoom: zoom)
    }

    /// すべての画像をほかのウィンドウより前に出す（最前面にしていない画像が隠れたとき用）
    func bringAllToFront() {
        pins.forEach { $0.bringToFront() }
    }

    /// クリック透過をすべてやめる
    func releaseClickThrough() {
        for pin in pins where pin.isClickThrough {
            pin.setClickThrough(false)
            pin.setOpacity(AppSettings.shared.defaultOpacity)
        }
    }

    func closeAll() {
        for pin in pins {
            pin.close()
        }
    }
}
