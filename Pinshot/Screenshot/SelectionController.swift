import AppKit
import Combine
import SwiftUI

/// 撮った画面を全画面に映し、その上で撮るもの（範囲・ウィンドウ・画面全体）を選ばせる
@MainActor
final class SelectionController {
    private var windows: [SelectionWindow] = []
    private var overlays: [SelectionView] = []
    private var modeBar: NSView?
    private var isDragging = false
    /// マウスのある画面（モードバーを置いている画面）
    private var activeWindowIndex: Int?
    /// マウスの動きを拾えなかったときのための、見回りのタイマー
    private var followTimer: Timer?
    /// 範囲選択の画面を出したときのマウスの位置（スクロールキャプチャで、見ていた場所を探すのに使う）
    private let options: CaptureOptions
    private let completion: (CaptureTarget?) -> Void
    private var finished = false
    private var keyMonitor: Any?
    /// キャプチャ中は、マウスが動くたびにキャプチャ用のカーソルを出し直す
    private var mouseMonitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    init(
        shots: [ScreenShot],
        windows windowInfos: [WindowInfo],
        options: CaptureOptions,
        completion: @escaping (CaptureTarget?) -> Void
    ) {
        self.options = options
        self.completion = completion

        for shot in shots {
            let window = SelectionWindow(screen: shot.screen)
            let size = shot.screen.frame.size
            let container = NSView(frame: NSRect(origin: .zero, size: size))

            // 撮った画面は NSImageView で映す（マウスを動かすたびに描き直さないように）
            let imageView = NSImageView(frame: container.bounds)
            imageView.image = NSImage(cgImage: shot.image, size: size)
            imageView.imageScaling = .scaleAxesIndependently
            imageView.autoresizingMask = [.width, .height]
            container.addSubview(imageView)

            let overlay = SelectionView(shot: shot, windows: windowInfos, options: options)
            overlay.frame = container.bounds
            overlay.autoresizingMask = [.width, .height]
            overlay.onSelect = { [weak self] target in self?.finish(target) }
            overlay.onCancel = { [weak self] in self?.finish(nil) }
            overlay.onDraggingChange = { [weak self] dragging in
                self?.isDragging = dragging
                self?.modeBar?.isHidden = dragging
                // ドラッグを終えたら、マウスのある画面にすぐ合わせる
                if !dragging { self?.followMouse() }
            }
            container.addSubview(overlay)

            window.contentView = container
            windows.append(window)
            overlays.append(overlay)
        }

        // モードを切り替えたら、すべての画面を描き直す
        options.$mode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                guard let self else { return }
                // スクロールに切り替えたら、撮るウィンドウをクリックで選んでもらう（マウスの下のスクロール領域を枠で示す）
                self.overlays.forEach { $0.modeDidChange() }
                self.applyCaptureCursor()
            }
            .store(in: &cancellables)
    }

    func begin() {
        // アプリ全体は前に出さない（前に撮った画像まで前に出てしまうため）。範囲を選ぶ画面だけを前に出してキーにする。
        // カーソルは、マウスが動くたびに十字を出し直して保つ
        for window in windows {
            window.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        for overlay in overlays {
            overlay.updatePointer(screenPoint: mouse)
        }

        let index = windows.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        guard windows.indices.contains(index) else { return }
        windows[index].makeKeyAndOrderFront(nil)
        windows[index].makeFirstResponder(overlays[index])
        // どのモードで撮るかが分かるよう、モードバーはいつも出す
        addModeBar(to: windows[index])
        activeWindowIndex = index
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.followMouse() }
        }

        // カーソルを十字にし、マウスが動くたびに出し直す（ほかのアプリにカーソルを戻されないように）
        CaptureCursors.selection.push()
        applyCaptureCursor()
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.followMouse()
                self?.applyCaptureCursor()
            }
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event)
            return event
        }) {
            mouseMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            mouseMonitors.append(global)
        }

        // esc と space は、どこにフォーカスがあっても受ける
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // esc
                self.finish(nil)
                return nil
            case 49: // space: 範囲 ⇄ ウィンドウ
                self.options.mode = self.options.mode == .window ? .region : .window
                return nil
            default:
                return event
            }
        }
    }

    /// 画面の下に、モードとタイマーを選ぶバーを出す
    private func addModeBar(to window: SelectionWindow) {
        let bar = FirstMouseHostingView(rootView: CaptureModeBar(
            options: options,
            cancel: { [weak self] in self?.finish(nil) }
        ))
        bar.frame.size = bar.fittingSize
        bar.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        modeBar = bar
        moveModeBar(to: window)
    }

    /// 2 つ以上の画面があるときは、マウスのある画面にバーを移す
    /// マウスのある画面が変わったら、モードバーと十字・座標の表示をそちらへ移す（2 つ以上の画面のとき）
    private func followMouse() {
        guard !finished else { return }
        let mouse = NSEvent.mouseLocation
        // 画面の境目ちょうどでも見つかるよう、少し広げて探す
        guard let index = windows.firstIndex(where: { $0.frame.contains(mouse) })
            ?? windows.firstIndex(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouse) }) else { return }
        guard index != activeWindowIndex else { return }
        // ドラッグ中は移さない（終えたら onDraggingChange から呼ばれる）
        guard !isDragging else { return }
        if let old = activeWindowIndex, overlays.indices.contains(old) {
            // 前の画面の十字・座標を消す
            overlays[old].updatePointer(screenPoint: mouse)
        }
        activeWindowIndex = index
        overlays[index].updatePointer(screenPoint: mouse)
        moveModeBar(to: windows[index])
    }

    private func moveModeBar(to window: SelectionWindow) {
        guard !isDragging, let bar = modeBar, let container = window.contentView, bar.superview !== container else { return }
        bar.removeFromSuperview()
        bar.frame.origin = NSPoint(x: ((container.bounds.width - bar.frame.width) / 2).rounded(), y: 56)
        container.addSubview(bar)
        if let overlay = overlays.first(where: { $0.window === window }) {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(overlay)
        }
    }

    /// いまのモードに合ったキャプチャ用のカーソル（範囲は ⌘⇧4 と同じ十字、ウィンドウ・画面全体はカメラ）
    private func applyCaptureCursor() {
        guard !finished else { return }
        // モードバーの上では、ボタンのカーソル（指）を優先する
        if let bar = modeBar, !bar.isHidden, let window = bar.window,
           bar.frame.contains(bar.superview?.convert(window.mouseLocationOutsideOfEventStream, from: nil) ?? .zero) {
            return
        }
        (options.mode.selectsRegion ? CaptureCursors.selection : CaptureCursors.window).set()
    }

    private func finish(_ target: CaptureTarget?) {
        guard !finished else { return }
        finished = true
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors.removeAll()
        followTimer?.invalidate()
        followTimer = nil
        NSCursor.pop()
        NSCursor.arrow.set()
        cancellables.removeAll()
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        overlays.removeAll()
        completion(target)
    }
}

/// 範囲を選ぶ画面のウィンドウ。アプリ全体を前に出さずにキー入力（esc・space）を受けられるパネルにする
/// （アプリを前に出すと、前に撮った画像まで一緒に前に出てしまうため）
final class SelectionWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        // フルスクリーンのアプリの上にも出す
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}
