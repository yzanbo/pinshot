import AppKit

/// 暗い膜・選んでいるもの・十字線・ルーペを描く（撮った画面そのものは下の NSImageView が映す）
final class SelectionView: NSView {
    var onSelect: ((CaptureTarget) -> Void)?
    var onCancel: (() -> Void)?
    var onDraggingChange: ((Bool) -> Void)?

    let shot: ScreenShot
    private let windowInfos: [WindowInfo]
    let options: CaptureOptions
    /// このビューの座標に直したウィンドウの位置（手前から順）
    private var windowRects: [(info: WindowInfo, rect: NSRect)] = []

    var pointer: NSPoint?
    private var start: NSPoint?
    var current: NSPoint?
    private var hoveredWindow: (info: WindowInfo, rect: NSRect)?
    private var lastDirtyRects: [NSRect] = []

    let loupeSize: CGFloat = 120
    /// ルーペで何ポイント四方を拡大するか
    let loupeSpan: CGFloat = 15
    let dimColor = NSColor.black.withAlphaComponent(0.35)
    /// シンプルな表示（画面を暗くせず、ルーペ・十字線を出さない。カーソルの横に座標を出す）
    let isSimple = !AppSettings.shared.detailedCaptureUI

    init(shot: ScreenShot, windows: [WindowInfo], options: CaptureOptions) {
        self.shot = shot
        self.windowInfos = windows
        self.options = options
        super.init(frame: NSRect(origin: .zero, size: shot.screen.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var mode: CaptureMode { options.mode }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        windowRects = windowInfos.compactMap { info in
            let rect = convert(window.convertFromScreen(info.frame), from: nil).intersection(bounds)
            return rect.width >= 8 && rect.height >= 8 ? (info, rect) : nil
        }
    }

    /// マウスの位置を伝える（選択を始めたときの初期位置用）
    func updatePointer(screenPoint: NSPoint) {
        guard let window, NSMouseInRect(screenPoint, window.frame, false) else {
            clearPointer()
            return
        }
        movePointer(to: convert(window.convertPoint(fromScreen: screenPoint), from: nil))
    }

    func modeDidChange() {
        start = nil
        current = nil
        if let pointer {
            hoveredWindow = windowRect(at: pointer)
        }
        window?.invalidateCursorRects(for: self)
        lastDirtyRects = []
        needsDisplay = true
    }

    /// マウスがこの画面から出たとき（マウスの下のウィンドウの枠・座標の表示を消す）
    private func clearPointer() {
        pointer = nil
        hoveredWindow = nil
        refresh()
    }

    /// point の下にある、いちばん手前のウィンドウ
    private func windowRect(at point: NSPoint) -> (info: WindowInfo, rect: NSRect)? {
        windowRects.first { $0.rect.contains(point) }
    }

    private func movePointer(to point: NSPoint) {
        pointer = point
        if start == nil {
            hoveredWindow = windowRect(at: point)
        }
        refresh()
    }

    // MARK: - カーソル

    private var cursor: NSCursor { CaptureCursors.cursor(for: options) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea([.mouseEnteredAndExited, .mouseMoved, .cursorUpdate])
    }

    /// マウスがモードバーの上にあるか（あるときは、バーのボタンのカーソル＝指に任せる）
    var isPointerOverModeBar: (() -> Bool)?

    /// キャプチャ用のカーソルを出す（モードバーの上では出さない。出すとボタンの指のカーソルと取り合ってちらつく）
    private func applyCursor() {
        guard isPointerOverModeBar?() != true else { return }
        cursor.set()
    }

    override func cursorUpdate(with event: NSEvent) { applyCursor() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }

    override func mouseMoved(with event: NSEvent) {
        applyCursor()
        movePointer(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        movePointer(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard start == nil else { return }
        clearPointer()
    }

    // MARK: - 描き直す範囲

    var selectionRect: NSRect? {
        guard options.selectsRegion, let start, let current else { return nil }
        return NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    /// 明るく抜く範囲
    var highlightRect: NSRect? {
        switch mode {
        case .region:
            if let rect = selectionRect, rect.width > 0, rect.height > 0 { return rect }
            // クリックではウィンドウを撮らないので、マウスの下のウィンドウは囲まない
            return nil
        case .record:
            if let rect = selectionRect, rect.width > 0, rect.height > 0 { return rect }
            // クリックで録画するもの（マウスの下のウィンドウ。なければ画面全体）を、いつも枠で示す
            guard start == nil, pointer != nil else { return nil }
            // ウィンドウだけを選ぶときは、ウィンドウのない所では何も示さない
            if options.recordsWindowOnly { return hoveredWindow?.rect.intersection(bounds) }
            return hoveredWindow?.rect.intersection(bounds) ?? bounds
        case .window:
            return hoveredWindow?.rect
        case .screen:
            return pointer == nil ? nil : bounds
        }
    }

    var highlightLabel: String? {
        guard let rect = highlightRect else { return nil }
        switch mode {
        case .record where selectionRect == nil:
            return hoveredWindow == nil
                ? "クリックで画面全体を録画　\(Int(rect.width)) × \(Int(rect.height))"
                : "クリックでこのウィンドウを録画　\(Int(rect.width)) × \(Int(rect.height))"
        case .region, .record:
            return "\(Int(rect.width)) × \(Int(rect.height))"
        case .window:
            return hoveredWindow?.info.displayName
        case .screen:
            return "画面全体　\(Int(rect.width)) × \(Int(rect.height))"
        }
    }

    /// 変わったところだけ描き直す（全画面を毎回描くと重いため）
    private func refresh() {
        var rects: [NSRect] = []
        if let rect = highlightRect {
            rects.append(rect.insetBy(dx: -4, dy: -4))
            if !isSimple || mode == .record, let label = highlightLabel {
                rects.append(labelRect(label, for: rect).insetBy(dx: -2, dy: -2))
            }
        }
        // シンプルな表示では、カーソルの横に座標を出す
        if options.selectsRegion, isSimple, let pointer {
            rects.append(coordinateLabelRect(at: pointer).insetBy(dx: -2, dy: -2))
        }
        if options.selectsRegion, !isSimple, let pointer {
            rects.append(NSRect(x: 0, y: pointer.y - 2, width: bounds.width, height: 4))
            rects.append(NSRect(x: pointer.x - 2, y: 0, width: 4, height: bounds.height))
            rects.append(loupeFrame(at: pointer).insetBy(dx: -4, dy: -4))
        }
        for rect in lastDirtyRects + rects {
            setNeedsDisplay(rect)
        }
        lastDirtyRects = rects
    }

    // 文字の見た目（描画は SelectionView+Drawing.swift）
    /// カーソルの横に出す座標（白い数字に黒い影）
    let coordinateAttributes: [NSAttributedString.Key: Any] = {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        return [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ]
    }()

    /// 枠の近くに出す、大きさ・名前のラベル
    let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    // MARK: - マウス

    private func clamped(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointer = point
        // クリックで選ぶウィンドウは、押した時点のものにする
        hoveredWindow = windowRect(at: point)
        if options.selectsRegion {
            start = point
            current = point
            onDraggingChange?(true)
        }
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        pointer = point
        if options.selectsRegion {
            current = point
        } else {
            hoveredWindow = windowRect(at: point)
        }
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        onDraggingChange?(false)
        switch mode {
        case .region:
            // ドラッグせずにクリックしたときは、何も撮らない（範囲はドラッグで選ぶ）
            guard let rect = selectionRect?.integral, rect.width >= 4, rect.height >= 4, let window else {
                start = nil
                current = nil
                refresh()
                return
            }
            onSelect?(.region(screen: shot.screen, rect: window.convertToScreen(convert(rect, to: nil))))

        case .record:
            // ドラッグしたときはその範囲、クリックしたときはマウスの下のウィンドウ（なければ画面全体）。
            // ウィンドウだけを選ぶときは、ウィンドウのない所を押しても何もしない
            if options.recordsWindowOnly, hoveredWindow == nil { return }
            let dragged = selectionRect.map { $0.width >= 4 && $0.height >= 4 } ?? false
            let rect = ((dragged ? selectionRect : nil) ?? hoveredWindow?.rect ?? bounds).intersection(bounds).integral
            guard rect.width >= 8, rect.height >= 8, let window else {
                start = nil
                current = nil
                refresh()
                return
            }
            onSelect?(.record(screen: shot.screen, rect: window.convertToScreen(convert(rect, to: nil))))

        case .window:
            guard let hovered = hoveredWindow else { return }
            onSelect?(.window(hovered.info))

        case .screen:
            onSelect?(.screen(shot.screen))
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }
}
