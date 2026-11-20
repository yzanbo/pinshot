import AppKit

extension PinCanvasView {
    // MARK: - マウス

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = imagePoint(viewPoint)

        // 文字の入力を終わらせたクリックは、確定するだけにする（同じクリックで新しい入力欄・番号などを作らない）。
        // ウィンドウは mouseDown を送る前に入力先をこのビューへ移すので、ここに来たときには入力はもう終わっている
        if let timestamp = textEndingClickTimestamp {
            textEndingClickTimestamp = nil
            if timestamp == event.timestamp { return }
        }

        // 書いた文字をダブルクリックすると直せる
        if event.clickCount == 2, let index = hitAnnotation(at: point), annotations[index].isText {
            if textField != nil {
                textCancelled = true
                window?.makeFirstResponder(self)
            }
            if !state.isEditing { controller?.setEditing(true) }
            beginReEdit(at: index, caretAt: event.locationInWindow)
            return
        }

        // 文字の入力中にほかをクリックしたら、入力を確定するだけ
        if textField != nil {
            window?.makeFirstResponder(self)
            return
        }

        // 文字を読み取る範囲を選んでいるときは、ドラッグで範囲を決める（画像の移動・描くことはしない）
        if isPickingTextRegion {
            dragStart = point
            textRegionDraft = CGRect(origin: point, size: .zero)
            needsDisplay = true
            return
        }

        // 選んだ書き込みのつまみをつかんだら、形を直す
        if state.isEditing, let handle = handle(at: viewPoint), let index = selectedIndex {
            handleDrag = (handle, annotations[index])
            handleChanged = false
            document.beginChange()
            updateSelectionBar()
            return
        }

        // 端をつかんだら大きさを変える
        if let drag = EdgeResizeDrag(edges: resizeEdges(at: viewPoint), window: window) {
            edgeResize = drag
            return
        }

        let flags = event.modifierFlags
        if !state.isEditing {
            if event.clickCount == 2 {
                // ダブルクリックで編集モードに入る（編集中のダブルクリックでは終わらない）
                controller?.setEditing(true)
            } else if flags.contains(.option) {
                // ⌥ を押しながらのドラッグで、画像をほかのアプリへ渡す
                beginDragOut(with: event)
            } else {
                moveWindow(with: event)
            }
            return
        }

        // 編集中でも、⌘ か space を押しながらのドラッグは画像の移動
        if flags.contains(.command) || isSpaceHeld {
            moveWindow(with: event)
            return
        }

        switch state.tool {
        case .select:
            if let index = hitAnnotation(at: point) {
                let id = annotations[index].id
                if flags.contains(.shift) {
                    // shift + クリックで、選択に足す・外す
                    if let position = selection.firstIndex(of: id) {
                        selection.remove(at: position)
                    } else {
                        selection.append(id)
                    }
                    needsDisplay = true
                    return
                }
                if !selection.contains(id) {
                    select(index)
                }
                HoverRole.movable.draggingCursor.set()
                moveStart = point
                moveOriginals = Dictionary(uniqueKeysWithValues: selectedIndices.map { (annotations[$0].id, annotations[$0]) })
                document.beginChange()
                didMove = false
                updateSelectionBar()
            } else {
                // 何もない所のドラッグは画像の移動
                selectedID = nil
                needsDisplay = true
                moveWindow(with: event)
            }
        case .text:
            if let index = hitAnnotation(at: point), annotations[index].isText {
                // 書いた文字をクリックしたら、その文字を直す（新しい入力欄を重ねない）
                beginReEdit(at: index, caretAt: event.locationInWindow)
            } else {
                beginTextInput(at: point, runs: [], color: state.drawColor, style: state.textStyle)
            }
        case .counter:
            addCounter(at: point)
        case .pen:
            dragStart = point
            drafting = makeAnnotation(.pen([point]))
        case .highlight:
            dragStart = point
            drafting = Annotation(shape: .highlight([point]), color: state.drawColor, lineWidth: state.lineWidth(for: .highlight))
        case .textMark:
            beginTextMark(at: point)
        case .crop:
            dragStart = point
            cropDraft = CGRect(origin: point, size: .zero)
        default:
            selectedID = nil
            dragStart = point
            drafting = makeAnnotation(from: point, to: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if let edgeResize {
            controller?.resize(with: edgeResize)
            return
        }

        let point = imagePoint(for: event)

        if textRegionDraft != nil, let start = dragStart {
            textRegionDraft = CGRect(corner: start, point)
            needsDisplay = true
            return
        }

        if let drag = handleDrag {
            dragHandle(drag.handle, original: drag.original, to: point, event: event)
            return
        }

        if let start = moveStart, !moveOriginals.isEmpty {
            let delta = CGVector(dx: point.x - start.x, dy: point.y - start.y)
            for original in moveOriginals.values {
                document.replace(original.translated(by: delta))
            }
            didMove = true
            needsDisplay = true
            return
        }

        guard let start = dragStart else { return }
        if cropDraft != nil {
            cropDraft = CGRect(corner: start, point)
        } else if case .textMark? = drafting?.shape {
            dragTextMark(to: point)
            return
        } else if case .pen(var points)? = drafting?.shape {
            points.append(point)
            drafting?.shape = .pen(points)
        } else if case .highlight(var points)? = drafting?.shape {
            if event.modifierFlags.contains(.shift) {
                // shift を押している間は、まっすぐ（45° ごと）に引く
                points = [start, constrained(point, from: start, event: event)]
            } else {
                points.append(point)
            }
            drafting?.shape = .highlight(points)
        } else {
            drafting = makeAnnotation(from: start, to: constrained(point, from: start, event: event))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if edgeResize != nil {
            edgeResize = nil
            updateCursor()
            return
        }

        if handleDrag != nil {
            document.endChange(keep: handleChanged)
            if handleChanged {
                historyChanged()
            }
            handleDrag = nil
            handleChanged = false
            updateSelectionBar()
            updateCursor()
            return
        }

        if moveStart != nil {
            document.endChange(keep: didMove)
            if didMove {
                historyChanged()
            }
            moveStart = nil
            moveOriginals = [:]
            updateSelectionBar()
            didMove = false
            updateCursor()
            return
        }

        if let draft = textRegionDraft {
            textRegionDraft = nil
            dragStart = nil
            endPickingTextRegion()
            // ドラッグせずにクリックしただけなら、見えている範囲すべてを読む
            let region = draft.width >= 4 && draft.height >= 4 ? draft : nil
            controller?.copyRecognizedText(in: region)
            return
        }

        if let draft = cropDraft {
            cropDraft = nil
            dragStart = nil
            applyCrop(draft)
            needsDisplay = true
            return
        }

        defer {
            dragStart = nil
            textMarkDragEnd = nil
            drafting = nil
            needsDisplay = true
            updateCursor()
        }
        guard let annotation = drafting, annotation.isMeaningful else { return }
        commit(annotation)
        if !annotation.editHandles.isEmpty {
            selectedID = annotation.id
        }
    }

    // MARK: - つまみ（描いたあとに形を直す）

    /// viewPoint の近くにある、選んだ書き込みのつまみ
    func handle(at viewPoint: NSPoint) -> EditHandle? {
        guard let index = selectedIndex else { return nil }
        let reach: CGFloat = 7
        for (handle, point) in annotations[index].editHandles {
            let p = viewRect(CGRect(origin: point, size: .zero)).origin
            if abs(p.x - viewPoint.x) <= reach, abs(p.y - viewPoint.y) <= reach {
                return handle
            }
        }
        return nil
    }

    private func dragHandle(_ handle: EditHandle, original: Annotation, to point: CGPoint, event: NSEvent) {
        guard document.index(of: original.id) != nil else { return }
        var updated = original
        switch handle {
        case .arrowStart, .arrowEnd:
            guard case .arrow(let from, let to, let style) = original.shape else { return }
            let fixed = handle == .arrowStart ? to : from
            // shift で 45° ごとにそろえる
            let moved = event.modifierFlags.contains(.shift) ? point.snappedTo45(from: fixed) : point
            updated.shape = handle == .arrowStart
                ? .arrow(from: moved, to: to, style: style)
                : .arrow(from: from, to: moved, style: style)
        case .rect(let edges):
            guard let rect = original.editableRect else { return }
            var minX = rect.minX
            var maxX = rect.maxX
            var minY = rect.minY
            var maxY = rect.maxY
            if edges.contains(.left) { minX = point.x }
            if edges.contains(.right) { maxX = point.x }
            if edges.contains(.top) { minY = point.y }
            if edges.contains(.bottom) { maxY = point.y }
            updated = original.withEditableRect(CGRect(corner: CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY)))
        }
        guard updated.isMeaningful else { return }
        document.replace(updated)
        handleChanged = true
        needsDisplay = true
    }

    /// 画像（ウィンドウ）をドラッグで動かす。動かしている間は握った手のカーソル
    private func moveWindow(with event: NSEvent) {
        HoverRole.movable.draggingCursor.set()
        window?.performDrag(with: event)
        controller?.windowDidFinishMoving()
        updateCursor()
    }

    /// shift を押しているときは、四角・楕円は正方形・正円、矢印は 45° 単位にそろえる
    private func constrained(_ point: CGPoint, from start: CGPoint, event: NSEvent) -> CGPoint {
        guard event.modifierFlags.contains(.shift) else { return point }
        let dx = point.x - start.x
        let dy = point.y - start.y
        switch state.tool {
        case .rectangle, .ellipse, .mosaic, .blur, .spotlight:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        case .arrow, .highlight:
            return point.snappedTo45(from: start)
        default:
            return point
        }
    }

    private func makeAnnotation(_ shape: Annotation.Shape) -> Annotation {
        Annotation(shape: shape, color: state.drawColor, lineWidth: state.lineWidth(for: state.tool))
    }

    private func makeAnnotation(from start: CGPoint, to end: CGPoint) -> Annotation {
        let shape: Annotation.Shape = switch state.tool {
        case .ellipse: .ellipse(CGRect(corner: start, end), style: state.ellipseStyle)
        case .arrow: .arrow(from: start, to: end, style: state.arrowStyle)
        case .mosaic: .mosaic(CGRect(corner: start, end))
        case .blur: .blur(CGRect(corner: start, end))
        case .spotlight: .spotlight(CGRect(corner: start, end))
        default: .rectangle(CGRect(corner: start, end), style: state.rectangleStyle)
        }
        return makeAnnotation(shape)
    }

    // MARK: - 番号

    private func addCounter(at point: CGPoint) {
        commit(Annotation(
            shape: .counter(document.nextCounterNumber, center: point, radius: state.counterSize.radius, style: state.counterStyle),
            color: state.drawColor,
            lineWidth: 0
        ))
    }

    // MARK: - トリミング

    private func applyCrop(_ draft: CGRect) {
        guard let old = document.crop(to: draft) else { return }
        controller?.cropDidChange(from: old, to: cropRect)
        historyChanged()
        showHUD("トリミングしました（⌘Z で戻す）")
    }

    override func scrollWheel(with event: NSEvent) {
        commitPendingText()
        let raw = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard raw != 0 else { return }
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            // ⌘ か ⌥ を押しながらスクロールで不透明度
            controller?.adjustOpacity(by: raw)
        } else {
            // 拡大縮小は、ゆっくり変わるよう不透明度の 1/3 の速さにする
            let zoomDelta = raw / 3
            controller?.zoom(by: min(max(1 + zoomDelta, 0.85), 1.15), around: NSEvent.mouseLocation)
        }
    }

    override func magnify(with event: NSEvent) {
        commitPendingText()
        controller?.zoom(by: 1 + event.magnification, around: NSEvent.mouseLocation)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        commitPendingText()
        return controller?.makeContextMenu()
    }

    // MARK: - ドラッグ＆ドロップで書き出す

    private func beginDragOut(with event: NSEvent) {
        guard
            let output = controller?.exportImage(),
            let png = ImageExporter.pngData(output.image, pointSize: output.pointSize)
        else { return }
        let image = output.image

        // Finder や Slack などにファイルとして渡せるよう、一時フォルダに PNG を書いておく
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(ImageExporter.defaultFileName())
        do {
            try png.write(to: url)
        } catch {
            return
        }

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(png, forType: .png)

        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let maxSide: CGFloat = 160
        let ratio = min(1, maxSide / max(bounds.width, bounds.height))
        let previewSize = NSSize(width: bounds.width * ratio, height: bounds.height * ratio)
        let p = convert(event.locationInWindow, from: nil)
        draggingItem.setDraggingFrame(
            NSRect(
                x: p.x - previewSize.width / 2,
                y: p.y - previewSize.height / 2,
                width: previewSize.width,
                height: previewSize.height
            ),
            contents: NSImage(cgImage: image, size: previewSize)
        )
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
