import AppKit

extension SelectionView {
    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        let highlight = highlightRect

        // 抜く範囲の外を暗くする（シンプルな表示では暗くしない）
        if !isSimple {
            let dim = NSBezierPath(rect: bounds)
            if let highlight {
                dim.append(NSBezierPath(rect: highlight))
                dim.windingRule = .evenOdd
            }
            dimColor.setFill()
            dim.fill()
        }

        if let highlight, isSimple, selectionRect != nil {
            // シンプルな表示：ドラッグした範囲をうっすら灰色にする
            NSColor(white: 0.5, alpha: 0.3).setFill()
            highlight.fill()
            NSColor(white: 1, alpha: 0.7).setStroke()
            let border = NSBezierPath(rect: highlight.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        } else if let highlight {
            if selectionRect != nil {
                // 明るい所でも暗い所でも見えるよう、黒と白の 2 重の線で囲む
                let outer = NSBezierPath(rect: highlight.insetBy(dx: -1.5, dy: -1.5))
                outer.lineWidth = 1
                NSColor.black.withAlphaComponent(0.5).setStroke()
                outer.stroke()
                NSColor.white.setStroke()
                let border = NSBezierPath(rect: highlight.insetBy(dx: -0.5, dy: -0.5))
                border.lineWidth = 1
                border.stroke()
            } else {
                // ウィンドウ・画面はアクセントカラーの枠で示す
                NSColor.controlAccentColor.setStroke()
                let border = NSBezierPath(rect: highlight.insetBy(dx: 1.5, dy: 1.5))
                border.lineWidth = 3
                border.stroke()
            }
            if !isSimple || mode == .scroll, let label = highlightLabel {
                drawLabel(label, in: labelRect(label, for: highlight))
            }
        }

        if mode.selectsRegion, !isSimple, let pointer {
            drawCrosshair(at: pointer)
            drawLoupe(at: pointer)
        }

        if mode.selectsRegion, isSimple, let pointer {
            drawCoordinates(at: pointer)
        }
    }

    // MARK: 座標（シンプルな表示。⌘⇧4 と同じく、カーソルの右下に白い数字を 2 行で出す）

    /// 画面の左上からの座標（ポイント）。横と縦を 2 行で
    private func coordinateText(at point: NSPoint) -> String {
        "\(Int(point.x))\n\(Int(point.y))"
    }

    /// カーソルの右下に置く。画面の端では反対側に回す
    func coordinateLabelRect(at point: NSPoint) -> NSRect {
        let text = coordinateText(at: point) as NSString
        let size = text.boundingRect(with: NSSize(width: 200, height: 100), options: [.usesLineFragmentOrigin], attributes: coordinateAttributes).size
        let labelSize = NSSize(width: ceil(size.width) + 4, height: ceil(size.height) + 4)
        var origin = NSPoint(x: point.x + 16, y: point.y + 14)
        if origin.x + labelSize.width > bounds.maxX - 2 { origin.x = point.x - 16 - labelSize.width }
        if origin.y + labelSize.height > bounds.maxY - 2 { origin.y = point.y - 14 - labelSize.height }
        return NSRect(origin: origin, size: labelSize)
    }

    private func drawCoordinates(at point: NSPoint) {
        let rect = coordinateLabelRect(at: point)
        (coordinateText(at: point) as NSString).draw(
            with: rect.insetBy(dx: 2, dy: 2),
            options: [.usesLineFragmentOrigin],
            attributes: coordinateAttributes
        )
    }

    private func drawCrosshair(at point: NSPoint) {
        let x = point.x.rounded(.down) + 0.5
        let y = point.y.rounded(.down) + 0.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: y))
        path.line(to: NSPoint(x: bounds.maxX, y: y))
        path.move(to: NSPoint(x: x, y: 0))
        path.line(to: NSPoint(x: x, y: bounds.maxY))
        path.lineWidth = 1
        NSColor.white.withAlphaComponent(0.55).setStroke()
        path.stroke()
    }

    // MARK: ルーペ

    /// ルーペ（と下の座標表示）を置く位置。画面の端ではカーソルの反対側に回す
    func loupeFrame(at point: NSPoint) -> NSRect {
        let size = NSSize(width: loupeSize, height: loupeSize + 26)
        let offset: CGFloat = 24
        var origin = NSPoint(x: point.x + offset, y: point.y + offset)
        if origin.x + size.width > bounds.maxX { origin.x = point.x - offset - size.width }
        if origin.y + size.height > bounds.maxY { origin.y = point.y - offset - size.height }
        return NSRect(origin: origin, size: size)
    }

    private func drawLoupe(at point: NSPoint) {
        let frame = loupeFrame(at: point)
        let lens = NSRect(x: frame.minX, y: frame.minY, width: loupeSize, height: loupeSize)

        let scaleX = CGFloat(shot.image.width) / bounds.width
        let scaleY = CGFloat(shot.image.height) / bounds.height
        let half = loupeSpan / 2
        // カーソルを中心にした範囲（画像のピクセル）
        let source = CGRect(
            x: (point.x - half) * scaleX,
            y: (point.y - half) * scaleY,
            width: loupeSpan * scaleX,
            height: loupeSpan * scaleY
        )
        let imageBounds = CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height)
        let clipped = source.intersection(imageBounds).integral

        NSGraphicsContext.saveGraphicsState()
        let shape = NSBezierPath(roundedRect: lens, xRadius: 10, yRadius: 10)
        shape.addClip()
        NSColor.black.setFill()
        lens.fill()

        if !clipped.isEmpty, let crop = shot.image.cropping(to: clipped) {
            // 画面の端で切り抜きが小さくなったぶん、描く位置をずらす
            let destination = NSRect(
                x: lens.minX + (clipped.minX - source.minX) / source.width * lens.width,
                y: lens.minY + (clipped.minY - source.minY) / source.height * lens.height,
                width: clipped.width / source.width * lens.width,
                height: clipped.height / source.height * lens.height
            )
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: crop, size: destination.size).draw(
                in: destination,
                from: .zero,
                operation: .copy,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSNumber(value: NSImageInterpolation.none.rawValue)]
            )
        }

        // 中心の 1 ポイントを枠で示す
        let cell = loupeSize / loupeSpan
        let center = NSRect(x: lens.midX - cell / 2, y: lens.midY - cell / 2, width: cell, height: cell)
        NSColor.black.withAlphaComponent(0.6).setStroke()
        NSBezierPath(rect: center.insetBy(dx: -1, dy: -1)).stroke()
        NSColor.white.setStroke()
        NSBezierPath(rect: center).stroke()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.85).setStroke()
        shape.lineWidth = 1.5
        shape.stroke()

        // 座標（画面の左上からのポイント）
        let text = "\(Int(point.x)), \(Int(point.y))"
        let size = (text as NSString).size(withAttributes: labelAttributes)
        let width = size.width + 12
        drawLabel(text, in: NSRect(x: lens.midX - width / 2, y: lens.maxY + 4, width: width, height: size.height + 6))
    }

    // MARK: ラベル

    func labelRect(_ text: String, for rect: NSRect) -> NSRect {
        let size = (text as NSString).size(withAttributes: labelAttributes)
        let labelSize = NSSize(width: min(size.width + 12, bounds.width), height: size.height + 6)
        var origin = NSPoint(x: rect.minX, y: rect.minY - labelSize.height - 4)
        if origin.y < 0 { origin.y = rect.minY + 6 }
        if !mode.selectsRegion || selectionRect == nil { origin.x += 6 }
        origin.x = min(max(origin.x, 0), bounds.maxX - labelSize.width)
        return NSRect(origin: origin, size: labelSize)
    }

    private func drawLabel(_ text: String, in rect: NSRect) {
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        let size = (text as NSString).size(withAttributes: labelAttributes)
        (text as NSString).draw(
            in: NSRect(x: rect.minX + 6, y: rect.midY - size.height / 2, width: rect.width - 12, height: size.height),
            withAttributes: labelAttributes
        )
    }
}
