import AppKit

extension PinCanvasView {
    // MARK: - カーソル

    /// 端をドラッグして大きさを変えられるか（表示モード、または編集中の選択ツール）
    private var canResize: Bool {
        (!state.isEditing || state.tool == .select) && bounds.width >= 40 && bounds.height >= 30
    }

    private var edgeZone: CGFloat { min(8, bounds.width / 6, bounds.height / 6) }

    func resizeEdges(at point: NSPoint) -> ResizeEdges {
        guard canResize else { return [] }
        let zone = edgeZone
        var edges: ResizeEdges = []
        if point.x < zone { edges.insert(.left) }
        if point.x > bounds.width - zone { edges.insert(.right) }
        if point.y < zone { edges.insert(.top) }
        if point.y > bounds.height - zone { edges.insert(.bottom) }
        return edges
    }

    /// マウスの位置・押しているキー・ツールに合ったカーソルにする
    func updateCursor() {
        // ツールバーのつまみで画像を動かしている間は、画像の上でもつかんだ手のままにする
        if controller?.isMovingWithToolbarHandle == true {
            HoverRole.movable.draggingCursor.set()
            return
        }
        guard let window, edgeResize == nil, moveStart == nil, dragStart == nil, handleDrag == nil else { return }
        // 画像に重なったツールバー・操作バーの上では、そちらのボタンがカーソルを決める
        guard isWindowFrontmostUnderMouse else { return }
        let viewPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(viewPoint) else { return }
        // 書き込みのバーの上は、そのボタンがカーソルを決める
        for subview in [selectionBar].compactMap({ $0 }) where !subview.isHidden && subview.frame.contains(viewPoint) {
            return
        }
        cursor(at: viewPoint).set()
    }

    private func cursor(at viewPoint: NSPoint) -> NSCursor {
        if state.isEditing, let handle = handle(at: viewPoint) {
            switch handle {
            case .arrowStart, .arrowEnd: return .crosshair
            case .rect(let edges): return resizeCursor(for: edges)
            }
        }
        let edges = resizeEdges(at: viewPoint)
        if !edges.isEmpty {
            return resizeCursor(for: edges)
        }
        let flags = NSEvent.modifierFlags
        if !state.isEditing {
            // ⌥ を押していればドラッグ＆ドロップ、そうでなければつかんで動かせる
            return flags.contains(.option) ? .dragCopy : HoverRole.movable.cursor
        }
        if isSpaceHeld || flags.contains(.command) {
            return HoverRole.movable.cursor
        }
        let point = imagePoint(viewPoint)
        switch state.tool {
        case .select:
            // 書き込み（文字も）の上なら、ドラッグで動かせることを示す手（文字はダブルクリックで直せる）
            return hitAnnotation(at: point) == nil ? HoverRole.inactive.cursor : HoverRole.movable.cursor
        case .text:
            return .iBeam
        case .counter:
            return .pointingHand
        default:
            return .crosshair
        }
    }

    override func resetCursorRects() {
        // カーソルは updateCursor で、マウスの位置に合わせて選ぶ
    }

    private func resizeCursor(for edges: ResizeEdges) -> NSCursor {
        edges.cursor
    }

    func refreshCursor() {
        updateCursor()
    }

    /// ツールが変わったとき
    func toolDidChange() {
        if state.tool != .select {
            selectedID = nil
        }
        refreshCursor()
        needsDisplay = true
    }
}
