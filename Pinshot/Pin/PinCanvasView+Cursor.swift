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
        return ResizeEdges.at(point, in: bounds, zone: edgeZone, flipped: true)
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
        if let selectionBar, !selectionBar.isHidden, selectionBar.frame.contains(viewPoint) { return }
        cursor(at: viewPoint).set()
    }

    private func cursor(at viewPoint: NSPoint) -> NSCursor {
        if state.isEditing, let handle = handle(at: viewPoint) {
            switch handle {
            case .arrowStart, .arrowEnd: return .crosshair
            case .rect(let edges): return edges.cursor
            }
        }
        // 文字を読み取る範囲を選んでいる間は、十字
        if isPickingTextRegion { return .crosshair }
        let edges = resizeEdges(at: viewPoint)
        if !edges.isEmpty {
            return edges.cursor
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

    /// ツールが変わったとき
    func toolDidChange() {
        if state.tool != .select {
            selectedID = nil
        }
        updateCursor()
        needsDisplay = true
    }
}
