import AppKit

/// 浮かせた画像のウィンドウの中身。背景を付けるときは、書き出しと同じ背景（余白・背景色・角丸・影）を描き、
/// その中に画像（キャンバス）を置く。背景を付けないときは、画像がウィンドウいっぱいになる
final class PinBackdropView: NSView {
    weak var controller: PinController?
    /// 中に置く画像（キャンバス）
    weak var content: NSView?

    /// 付ける背景（nil なら付けない）
    var decoration: ExportDecoration? {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    /// いまの拡大率（余白・角丸・影も一緒に拡大する）
    var zoom: CGFloat = 1 {
        didSet {
            needsLayout = true
            needsDisplay = true
        }
    }

    /// 外側の端をつかんで大きさを変えている間の状態
    private var edgeResize: EdgeResizeDrag?

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 画像のまわりの余白（画面上のポイント）
    var inset: CGFloat { (decoration?.padding.points ?? 0) * zoom }

    override func layout() {
        super.layout()
        guard let content else { return }
        content.frame = bounds.insetBy(dx: inset, dy: inset)
        content.wantsLayer = true
        // 背景を付けるときは、書き出しと同じく画像の角を丸める
        let radius = decoration.map { min($0.corner.points * zoom, min(content.frame.width, content.frame.height) / 2) } ?? 0
        content.layer?.cornerRadius = radius
        content.layer?.masksToBounds = radius > 0
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let decoration, let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 背景（単色か、左上から右下へのグラデーション）
        let colors = decoration.background.colors
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if colors.count >= 2,
           let gradient = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bounds.maxY), end: CGPoint(x: bounds.maxX, y: 0), options: [])
        } else if let color = colors.first {
            ctx.setFillColor(color.cgColor)
            ctx.fill(bounds)
        }

        // 画像の下に落とす影
        guard decoration.shadow, let content else { return }
        let frame = content.frame
        let radius = min(decoration.corner.points * zoom, min(frame.width, frame.height) / 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * zoom), blur: 28 * zoom, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // MARK: - 余白の部分の操作（画像の上の操作はキャンバスが受ける）

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea([.mouseMoved, .cursorUpdate])
    }

    private var edgeZone: CGFloat { max(6, min(10, inset / 2)) }

    private func cursor(at point: NSPoint) -> NSCursor? {
        // 画像の上は、キャンバスがカーソルを決める
        if let content, content.frame.contains(point) { return nil }
        let edges = ResizeEdges.at(point, in: bounds, zone: edgeZone, flipped: false)
        return edges.isEmpty ? .openHand : edges.cursor
    }

    override func mouseMoved(with event: NSEvent) {
        backdropCursor(at: convert(event.locationInWindow, from: nil))?.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        backdropCursor(at: convert(event.locationInWindow, from: nil))?.set()
    }

    /// ツールバーのつまみで画像を動かしている間は、つかんだ手のままにする
    private func backdropCursor(at point: NSPoint) -> NSCursor? {
        if controller?.isMovingWithToolbarHandle == true { return .closedHand }
        return cursor(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // 背景の外側の端をつかんだら、大きさを変える
        let edges = ResizeEdges.at(point, in: bounds, zone: edgeZone, flipped: false)
        if let drag = EdgeResizeDrag(edges: edges, window: window) {
            edgeResize = drag
            return
        }
        if event.clickCount == 2 {
            controller?.setEditing(true)
            return
        }
        NSCursor.closedHand.set()
        window?.performDrag(with: event)
        controller?.windowDidFinishMoving()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let edgeResize else { return }
        controller?.resize(with: edgeResize)
    }

    override func mouseUp(with event: NSEvent) {
        edgeResize = nil
    }

    override func scrollWheel(with event: NSEvent) {
        content?.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        content?.magnify(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.makeContextMenu()
    }
}
