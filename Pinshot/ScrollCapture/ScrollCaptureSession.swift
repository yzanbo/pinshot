import AppKit
import ScreenCaptureKit
import SwiftUI

/// 1 回のスクロールキャプチャ
@MainActor
final class ScrollCaptureSession {
    struct Output {
        let image: CGImage
        let pointSize: CGSize
    }

    private let screen: NSScreen
    private let rect: NSRect
    private let window: WindowInfo?
    private let scrollPoint: NSPoint?
    private let completion: (Output?) -> Void
    private let model = ScrollCaptureModel()

    private var panel: NSPanel?
    private var border: NSWindow?
    private var task: Task<Void, Never>?
    private var keyMonitors: [Any] = []
    private var finished = false

    private var stitch: ScrollStitch?
    private var lastSignature: FrameSignature?
    /// スクロールの向き（下へスクロールする値の符号。最初の結果で確かめて、逆なら入れ替える）
    private var scrollSign: CGFloat = -1
    private var directionConfirmed = false
    private var triedFlippingDirection = false
    /// 1 回にスクロールする量（ポイント）
    private var stepPoints: CGFloat
    private var unchangedCount = 0
    /// 自動スクロールで、続けてつなげなかった回数
    private var lostCount = 0
    /// 直前に送ったスクロールの量（つなげなかったとき、同じだけ戻すため）
    private var lastScroll: CGFloat = 0
    /// つなげなかったので、送ったスクロールを戻す必要がある
    private var needsScrollBack = false
    /// 自動スクロールで続けてつなげなかったら、自分でスクロールしてもらう回数
    private let maxLostCount = 3

    /// つなげる長さの上限（ピクセル）
    private let maxHeightPixels = 30_000

    init(screen: NSScreen, rect: NSRect, window: WindowInfo?, scrollPoint: NSPoint?, completion: @escaping (Output?) -> Void) {
        self.screen = screen
        self.rect = rect
        self.window = window
        self.scrollPoint = scrollPoint
        self.completion = completion
        self.stepPoints = max(40, rect.height * 0.5)
    }

    func start() {
        model.finish = { [weak self] in self?.end(keep: true) }
        model.cancel = { [weak self] in self?.end(keep: false) }

        // 浮かせている画像がスクロール操作を受けてしまわないよう、しばらくマウスを通す
        PinManager.shared.setMouseEventsSuspended(true)
        showBorder()
        showPanel()
        installKeyMonitors()
        if !AccessibilityPermission.isGranted {
            // 許可がないと、ほかのアプリの上で押したキーは届かない。操作パネルでキー（esc）を受けられるようにする
            panel?.makeKey()
        }

        if let window {
            // 撮るウィンドウを前に出す（隠れていると、上のウィンドウにスクロールが送られたり、上のウィンドウが写ったりするため）
            ScrollTargetFinder.raise(window)
        }
        if AccessibilityPermission.isGranted {
            moveCursorIntoRegion()
        }
        task = Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    // MARK: - 撮影のくり返し

    private func run() async {
        do {
            if window != nil {
                // 前に出したウィンドウが描き終わるのを待つ
                try await Task.sleep(for: .milliseconds(350))
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let filter = makeFilter(content: content) else {
                model.message = "画面が見つかりませんでした"
                return
            }

            let first = try await capture(filter: filter)
            stitch = ScrollStitch(first: first)
            lastSignature = FrameSignature(image: first)
            updatePreview()

            while !finished, !Task.isCancelled {
                let trusted = AccessibilityPermission.isGranted
                model.isTrusted = trusted
                let auto = trusted && model.autoScroll

                let frame: CGImage
                let signature: FrameSignature?
                // マウスが枠の外にあるとき・ほかのウィンドウが重なったときは、スクロールを送らない（送ると別のものが動く）
                let scrolls = auto && isCursorInRegion && isTargetUnderCursor
                if scrolls {
                    model.message = "自動でスクロールしています…"
                    lastScroll = stepPoints * scrollSign
                    postScroll(points: lastScroll)
                    (frame, signature) = try await captureWhenStill(filter: filter)
                } else {
                    if auto {
                        model.message = isCursorInRegion
                            ? "撮っているウィンドウの上にほかのウィンドウがあるので、止めています"
                            : "マウスを枠の中に戻すと、自動スクロールを続けます"
                    } else if !trusted {
                        model.message = "枠の中を、ゆっくり下へスクロールしてください"
                    } else {
                        model.message = "自分でスクロールしています。ゆっくり下へ"
                    }
                    try await Task.sleep(for: .milliseconds(120))
                    guard !finished else { break }
                    frame = try await capture(filter: filter)
                    signature = FrameSignature(image: frame)
                }
                guard !finished, let signature else { continue }
                process(frame, signature: signature, scrolled: scrolls, auto: auto)
                if needsScrollBack, !finished {
                    // つなげなかったぶんを戻してから、少ない量でやり直す
                    needsScrollBack = false
                    postScroll(points: -lastScroll)
                    _ = try await captureWhenStill(filter: filter)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            model.message = "撮れませんでした: \(error.localizedDescription)"
        }
    }

    /// scrolled: この画像の前に、自動でスクロールを送ったか。auto: 自動スクロールのモードか
    private func process(_ frame: CGImage, signature: FrameSignature, scrolled: Bool, auto: Bool) {
        guard let stitch, let previous = lastSignature else { return }

        switch ScrollStitcher.findOffset(previous: previous, next: signature, header: stitch.header, footer: stitch.footer) {
        case .moved(let match):
            directionConfirmed = true
            unchangedCount = 0
            lostCount = 0
            model.warning = nil
            stitch.append(frame, match: match)
            lastSignature = signature
            updatePreview()
            if stitch.totalHeight >= maxHeightPixels {
                model.warning = "長さの上限に達したので終了しました"
                end(keep: true)
            }

        case .unchanged:
            // スクロールを送っていないときは、変わらなくて当たり前なので数えない
            guard scrolled else { return }
            // 向きがまだ分からないうちに変化がなければ、一度だけ逆向きを試す（ページの上端で上へ送っていた場合）
            if !directionConfirmed, !triedFlippingDirection {
                triedFlippingDirection = true
                scrollSign *= -1
                return
            }
            unchangedCount += 1
            // スクロールしても変わらなければ、いちばん下まで来たとみなす
            if unchangedCount >= 2 {
                end(keep: true)
            }

        case .lost:
            // 上にスクロールしていないかを確かめる
            if case .moved = ScrollStitcher.findOffset(previous: signature, next: previous) {
                if scrolled, !directionConfirmed {
                    // 送ったスクロールの向きが逆だった（システムの設定による）。向きを入れ替える
                    scrollSign *= -1
                    lastSignature = signature
                    self.stitch = ScrollStitch(first: frame)
                    updatePreview()
                } else if !auto {
                    model.warning = "上へのスクロールは撮りません。下へスクロールしてください"
                }
                return
            }
            if scrolled {
                lostCount += 1
                if lostCount >= maxLostCount {
                    // 何度やってもつなげない（動き続ける広告・動画など）。自動はやめて、自分でスクロールしてもらう
                    lostCount = 0
                    model.autoScroll = false
                    model.warning = "自動ではつなげませんでした。自分でゆっくりスクロールするか、「完了」を押してください"
                } else {
                    // 重なりが見つからない（1 回のスクロールが大きすぎる）。戻してから、量を減らしてやり直す
                    stepPoints = max(30, stepPoints * 0.6)
                    needsScrollBack = true
                    model.warning = "スクロール量を減らして続けています"
                }
            } else if !auto {
                model.warning = "速すぎてつなげませんでした。少し戻してから、ゆっくりスクロールしてください"
            }
        }
    }

    private func updatePreview() {
        guard let stitch else { return }
        let scale = CGFloat(stitch.width) / max(rect.width, 1)
        model.heightPoints = Int(CGFloat(stitch.totalHeight) / scale)
        if let image = stitch.preview() {
            model.preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    // MARK: - 撮る

    /// 自分のアプリのウィンドウ（操作パネル・枠・浮かせた画像）は写さない
    private func makeFilter(content: SCShareableContent) -> SCContentFilter? {
        guard
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
            let display = content.displays.first(where: { $0.displayID == number })
        else { return nil }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let mine = content.applications.filter { $0.processID == myPID }
        return SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
    }

    private func capture(filter: SCContentFilter) async throws -> CGImage {
        let config = SCStreamConfiguration()
        // 画面の左上を原点にした、枠の範囲（ポイント）
        let local = CGRect(
            x: rect.minX - screen.frame.minX,
            y: screen.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        let scale = screen.backingScaleFactor
        config.sourceRect = local
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// スクロールのアニメーションが止まるまで撮り直し、止まった画像を返す
    private func captureWhenStill(filter: SCContentFilter) async throws -> (CGImage, FrameSignature?) {
        try await Task.sleep(for: .milliseconds(120))
        var image = try await capture(filter: filter)
        var signature = FrameSignature(image: image)
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(90))
            let next = try await capture(filter: filter)
            let nextSignature = FrameSignature(image: next)
            if nextSignature == signature {
                return (next, nextSignature)
            }
            image = next
            signature = nextSignature
        }
        return (image, signature)
    }

    // MARK: - 自動スクロール

    private var isCursorInRegion: Bool {
        rect.insetBy(dx: 2, dy: 2).contains(NSEvent.mouseLocation)
    }

    /// マウスの下にあるのが、撮っているウィンドウ（のアプリ）か。
    /// ⌘Tab などでほかのウィンドウが重なったら、そちらをスクロールしないよう止める（範囲をドラッグで選んだときは確かめない）
    private var isTargetUnderCursor: Bool {
        guard let window else { return true }
        let mouse = NSEvent.mouseLocation
        guard let top = WindowList.visibleWindows().first(where: { $0.frame.contains(mouse) }) else { return true }
        return top.ownerPID == window.ownerPID
    }

    /// スクロール操作はマウスの下に届くので、マウスを範囲の中に置く（クリックした場所があればそこ、なければ真ん中）
    private func moveCursorIntoRegion() {
        let inner = rect.insetBy(dx: 8, dy: 8)
        let point = scrollPoint.flatMap { inner.contains($0) ? $0 : nil } ?? NSPoint(x: rect.midX, y: rect.midY)
        // CGWarpMouseCursorPosition は「メインの画面の左上が原点」の座標
        CGWarpMouseCursorPosition(ScreenGeometry.quartzPoint(point))
    }

    /// マウスの下のウィンドウに、スクロール操作を送る（アクセシビリティの許可が必要）
    private func postScroll(points: CGFloat) {
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(points.rounded()),
            wheel2: 0,
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    // MARK: - 終わる

    private func end(keep: Bool) {
        guard !finished else { return }
        finished = true
        task?.cancel()
        task = nil
        for monitor in keyMonitors {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitors.removeAll()
        panel?.orderOut(nil)
        border?.orderOut(nil)
        panel = nil
        border = nil
        PinManager.shared.setMouseEventsSuspended(false)

        guard keep, let stitch, let image = stitch.compose() else {
            completion(nil)
            return
        }
        let scale = CGFloat(stitch.width) / max(rect.width, 1)
        completion(Output(image: image, pointSize: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)))
    }

    private func installKeyMonitors() {
        // esc で終える（ほかのアプリが前に出ていても受けられるよう、両方で見る）
        let handler: (NSEvent) -> Void = { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.end(keep: true) }
            }
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event.keyCode == 53 ? nil : event
        }) {
            keyMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            keyMonitors.append(global)
        }
    }

    // MARK: - 枠と操作パネル

    /// 撮っている範囲を、外側の点線で示す（範囲の内側には描かないので写らない）
    private func showBorder() {
        let frame = rect.insetBy(dx: -4, dy: -4)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = ScrollBorderView(frame: NSRect(origin: .zero, size: frame.size))
        window.orderFrontRegardless()
        border = window
    }

    private func showPanel() {
        let hosting = FirstMouseHostingView(rootView: ScrollCapturePanelView(model: model))
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let gap: CGFloat = 14

        // 枠の下 → 上 → 右 → 左 の順に、画面に収まる場所へ置く
        let candidates = [
            NSPoint(x: rect.midX - size.width / 2, y: rect.minY - gap - size.height),
            NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + gap),
            NSPoint(x: rect.maxX + gap, y: rect.midY - size.height / 2),
            NSPoint(x: rect.minX - gap - size.width, y: rect.midY - size.height / 2),
        ]
        var origin = candidates.first { visible.contains(NSRect(origin: $0, size: size)) }
            ?? NSPoint(x: visible.maxX - size.width - 16, y: visible.minY + 16)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)

        let panel = KeyableOverlayPanel(contentRect: NSRect(origin: origin, size: size), level: .statusBar)
        panel.isMovableByWindowBackground = true
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
