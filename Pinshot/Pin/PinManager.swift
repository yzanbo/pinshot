import AppKit

/// 浮かせている画像をまとめて持つ
@MainActor
final class PinManager {
    static let shared = PinManager()

    private var pins: [PinController] = []

    /// 閉じた画像（新しい順、最大 10 枚）。「閉じた画像を戻す」で使う
    private var closedPins: [ClosedPin] = []
    private let maxClosedPins = 10
    /// ときどき保存するためのタイマー（startAutosave）
    private var autosaveTimer: Timer?
    /// 浮かせた・閉じたあとに、少し待って保存する予定があるか
    private var isSaveScheduled = false

    /// 閉じた画像（状態と、元の画像）
    private struct ClosedPin {
        let saved: SavedPin
        let image: CGImage
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

    /// 撮った画像を浮かせ、撮った画像の履歴にも残す。
    /// zoom: 最初の倍率（frame はこの倍率をかけた大きさで渡す）
    func pin(image: CGImage, imageSize: CGSize, frame: NSRect, zoom: CGFloat = 1) {
        // 履歴の印を付けておく（あとで履歴から同じ画像を浮かせたときに、増やさずこの画像を前に出す）
        let historyID = CaptureHistory.shared.add(image: image, pointSize: imageSize)
        let controller = show(image: image, imageSize: imageSize, frame: frame, zoom: zoom, origin: historyID.map(PinOrigin.captureHistory))
        // 設定の「撮ったら、クリップボードにもコピーする」（初期設定はオフ）。
        // 撮ったときだけ（履歴・クリップボードから浮かせたときは、クリップボードを上書きしない）
        if AppSettings.shared.copyAfterCapture {
            ImageExporter.writeToPasteboard(image, pointSize: imageSize)
            controller.canvas.showHUD("コピーしました")
        }
        // 設定の「撮ったら自動で上げる」（初期設定はオフ）。上げるのは撮ったままの画像
        if AppSettings.shared.autoUploadCaptures {
            UploadCenter.shared.shareImage(image, pointSize: imageSize, automatic: true) { [weak controller] status in
                controller?.canvas.showUploadStatus(status)
            }
        }
    }

    /// 画像を浮かせる（履歴には残さない）
    @discardableResult
    private func show(image: CGImage, imageSize: CGSize, frame: NSRect, zoom: CGFloat, origin: PinOrigin? = nil) -> PinController {
        let controller = makeController(image: image, imageSize: imageSize, frame: frame, zoom: zoom)
        controller.origin = origin
        controller.show()
        scheduleSave()
        return controller
    }

    private func makeController(
        id: UUID = UUID(),
        image: CGImage,
        imageSize: CGSize,
        frame: NSRect,
        zoom: CGFloat,
        restoring: SavedPin? = nil
    ) -> PinController {
        let controller = PinController(id: id, image: image, imageSize: imageSize, frame: frame, zoom: zoom, restoring: restoring)
        controller.onClose = { [weak self] closed in
            self?.didClose(closed)
        }
        pins.append(controller)
        return controller
    }

    private func didClose(_ controller: PinController) {
        pins.removeAll { $0 === controller }
        closedPins.insert(ClosedPin(saved: controller.savedPin, image: controller.canvas.baseImage), at: 0)
        if closedPins.count > maxClosedPins {
            closedPins.removeLast(closedPins.count - maxClosedPins)
        }
        scheduleSave()
    }

    /// 最後に閉じた画像を、書き込みごと元の場所に戻す
    func restoreLastClosed() {
        guard !closedPins.isEmpty else {
            NSSound.beep()
            return
        }
        let closed = closedPins.removeFirst()
        reopen(closed.saved, image: closed.image, makesKey: true)
        scheduleSave()
    }

    /// 残しておいた状態から、画像を元の場所に浮かせ直す（閉じた画像を戻すとき・起動したとき）。
    /// makesKey: キーにする（起動したときは、ほかのアプリの操作を奪わないよう前に出すだけ）
    @discardableResult
    private func reopen(_ saved: SavedPin, image: CGImage, makesKey: Bool) -> PinController {
        let controller = makeController(
            id: saved.id,
            image: image,
            imageSize: saved.imageSize,
            frame: saved.frame,
            zoom: saved.zoom,
            restoring: saved
        )
        controller.setOpacity(saved.opacity, showsHUD: false)
        if makesKey { controller.show() } else { controller.bringToFront() }
        // 画面の並びが変わっていたら、見える画面の中に戻す
        controller.ensureOnScreen()
        return controller
    }

    /// クリップボードの画像を、マウスのある画面の真ん中に浮かせる。画像がなければ false
    @discardableResult
    func pinClipboardImage() -> Bool {
        guard
            let image = NSImage(pasteboard: .general),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            image.size.width >= 1, image.size.height >= 1
        else { return false }
        pinAtMouseScreen(image: cgImage, imageSize: image.size)
        return true
    }

    /// origin の画像がもう浮いていれば、新しく浮かせずに前に出してキーにする（「すでに浮かせています」と知らせる）。
    /// 浮いていなければ false（呼ぶ側が画像を読んで浮かせる）
    private func focusPin(from origin: PinOrigin) -> Bool {
        guard let existing = pins.last(where: { $0.origin == origin }) else { return false }
        existing.show()
        existing.ensureOnScreen()
        existing.canvas.showHUD("すでに浮かせています")
        return true
    }

    /// 履歴の画像を浮かせる。同じ画像がもう浮いていれば、増やさずにそれを前に出す。
    /// 新しく浮かせたら true（続けて浮かせるときに、ずらす数を数えるため）
    @discardableResult
    func pinFromHistory(_ origin: PinOrigin, offset: CGFloat = 0, load: () -> (image: CGImage, size: CGSize)?) -> Bool {
        if focusPin(from: origin) { return false }
        guard let (image, size) = load() else {
            NSSound.beep()
            return false
        }
        pinAtMouseScreen(image: image, imageSize: size, offset: offset, origin: origin)
        return true
    }

    /// 画像を、マウスのある画面の真ん中に浮かせる（クリップボード・履歴から。履歴には残さない）。
    /// offset: 続けて浮かせるときに、右下へずらす量
    func pinAtMouseScreen(image: CGImage, imageSize size: CGSize, offset: CGFloat = 0, origin: PinOrigin? = nil) {
        let visible = ScreenGeometry.screen(containing: NSEvent.mouseLocation)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // 大きい画像は、画面の 7 割に収まるよう縮める
        let zoom = min(1, visible.width * 0.7 / size.width, visible.height * 0.7 / size.height)
        let frame = NSRect(
            x: visible.midX - size.width * zoom / 2 + offset,
            y: visible.midY - size.height * zoom / 2 - offset,
            width: size.width * zoom,
            height: size.height * zoom
        )
        show(image: image, imageSize: size, frame: frame, zoom: zoom, origin: origin)
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

    /// 編集中の画像があれば、編集を終える（書きかけの文字も確定する）。履歴のウィンドウを開くときに使う
    func endEditing() {
        for pin in pins where pin.state.isEditing {
            pin.setEditing(false)
        }
    }

    func closeAll() {
        for pin in pins {
            pin.close()
        }
    }

    // MARK: - 終了・再起動のあとも残す

    /// 浮かせている画像と閉じた画像を保存する（戻さない設定のときは、保存したものを消す）。
    /// wait: 書き終えるまで待つ（終了するとき）
    func saveSession(wait: Bool = false) {
        let store = PinSessionStore.shared
        guard AppSettings.shared.restorePins else {
            store.clear(wait: wait)
            return
        }
        var images: [String: (image: CGImage, size: CGSize)] = [:]
        var session = SavedPinSession()
        for pin in pins {
            // 入力中の文字は確定してから残す
            if wait { pin.canvas.commitPendingText() }
            let saved = pin.savedPin
            session.pins.append(saved)
            images[saved.imageFileName] = (pin.canvas.baseImage, pin.canvas.imageSize)
        }
        for closed in closedPins {
            session.closed.append(closed.saved)
            images[closed.saved.imageFileName] = (closed.image, closed.saved.imageSize)
        }
        store.save(session, images: images, wait: wait)
    }

    /// 起動したとき、前に浮かせていた画像を元の場所に戻し、閉じた画像も「閉じた画像を戻す」で戻せるようにする
    func restoreSession() {
        guard AppSettings.shared.restorePins, let (session, images) = PinSessionStore.shared.load() else { return }
        for saved in session.pins {
            guard let image = images[saved.id] else { continue }
            reopen(saved, image: image, makesKey: false)
        }
        closedPins = session.closed.prefix(maxClosedPins).compactMap { saved in
            images[saved.id].map { ClosedPin(saved: saved, image: $0) }
        }
    }

    /// 浮かせた・閉じたあとに、少し待って保存する（続けて起きたときは 1 回にまとめる）
    private func scheduleSave() {
        guard !isSaveScheduled else { return }
        isSaveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.isSaveScheduled = false
            self?.saveSession()
        }
    }

    /// 動いている間も、ときどき保存する（強制終了したときに、少し前の状態までは戻せるように）
    func startAutosave() {
        guard autosaveTimer == nil else { return }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { PinManager.shared.saveSession() }
        }
    }
}
