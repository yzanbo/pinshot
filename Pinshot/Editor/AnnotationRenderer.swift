import AppKit

/// 書き込みを描く。画面表示と書き出しの両方で同じ処理を使う。
/// 前提: 現在の NSGraphicsContext は flipped（左上が原点）で、CTM は「画像のポイント座標」に合わせてある。
enum AnnotationRenderer {
    /// shadow: 書き込みに薄い影を付けて、背景に埋もれないようにする
    static func draw(
        _ annotations: [Annotation],
        in ctx: CGContext,
        imageSize: CGSize,
        effects: EffectImages,
        shadow: Bool = true
    ) {
        // スポットライトは、ほかの書き込みより先に（下に）まとめて描く
        let spotlights = annotations.compactMap { annotation -> CGRect? in
            if case .spotlight(let rect) = annotation.shape { return rect.standardized }
            return nil
        }
        if !spotlights.isEmpty {
            drawSpotlights(spotlights, imageSize: imageSize, in: ctx)
        }
        for annotation in annotations where !annotation.isSpotlight {
            draw(annotation, in: ctx, imageSize: imageSize, effects: effects, shadow: shadow)
            // モザイク・ぼかしは元の画像から作った画像で塗り替えるので、スポットライトの暗さを、その範囲にもう一度かける
            if !spotlights.isEmpty, let rect = effectRect(of: annotation) {
                ctx.saveGState()
                ctx.clip(to: rect.standardized)
                drawSpotlights(spotlights, imageSize: imageSize, in: ctx)
                ctx.restoreGState()
            }
        }
    }

    /// モザイク・ぼかしの範囲（ほかの書き込みは nil）
    private static func effectRect(of annotation: Annotation) -> CGRect? {
        switch annotation.shape {
        case .mosaic(let rect), .blur(let rect): rect
        case .rectangle, .ellipse, .arrow, .pen, .highlight, .textMark, .text, .counter, .spotlight: nil
        }
    }

    /// 画像全体を暗くして、スポットライトの範囲だけ元の明るさに戻す
    private static func drawSpotlights(_ rects: [CGRect], imageSize: CGSize, in ctx: CGContext) {
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(CGRect(origin: .zero, size: imageSize))
        ctx.setBlendMode(.clear)
        for rect in rects {
            let radius = min(6, rect.width / 4, rect.height / 4)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    static func draw(
        _ annotation: Annotation,
        in ctx: CGContext,
        imageSize: CGSize,
        effects: EffectImages,
        shadow: Bool = true
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        // 矢印の線と矢じりの影が重ならないよう、1 枚にまとめてから影を付ける
        let usesShadow = shadow && !annotation.isEffect && !annotation.isTranslucentMarker
        if usesShadow {
            ctx.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.4).cgColor)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer {
            if usesShadow { ctx.endTransparencyLayer() }
        }

        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setFillColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch annotation.shape {
        case .rectangle(let rect, let style):
            let rect = rect.standardized
            let radius = style.corner.radius(for: rect)
            let path = radius > 0
                ? CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                : CGPath(rect: rect, transform: nil)
            drawShape(path, fill: style.fill, color: annotation.color, in: ctx)

        case .ellipse(let rect, let style):
            drawShape(CGPath(ellipseIn: rect.standardized, transform: nil), fill: style.fill, color: annotation.color, in: ctx)

        case .highlight(let points):
            drawHighlight(points, color: annotation.color, lineWidth: annotation.lineWidth, in: ctx)

        case .textMark(let rects, let style):
            drawTextMark(rects, style: style, color: annotation.color, lineWidth: annotation.lineWidth, in: ctx)

        case .counter(let number, let center, let radius, let style):
            drawCounter(number, center: center, radius: radius, style: style, color: annotation.color, in: ctx)

        case .arrow(let from, let to, let style):
            drawArrow(from: from, to: to, lineWidth: annotation.lineWidth, style: style, in: ctx)

        case .pen(let points):
            guard points.count > 1 else { return }
            ctx.beginPath()
            ctx.addLines(between: points)
            ctx.strokePath()

        case .text(let runs, let origin, let style, let width):
            drawText(runs, origin: origin, width: width, style: style, color: annotation.color, in: ctx)

        case .mosaic(let rect):
            // 画像全体をモザイクにした画像を、選んだ範囲だけ切り抜いて重ねる
            drawEffect(effects.pixelated, clippedTo: rect, imageSize: imageSize, in: ctx)

        case .blur(let rect):
            drawEffect(effects.blurred, clippedTo: rect, imageSize: imageSize, in: ctx)

        case .spotlight:
            break // まとめて描く（drawSpotlights）
        }
    }

    private static func drawEffect(_ image: NSImage?, clippedTo rect: CGRect, imageSize: CGSize, in ctx: CGContext) {
        guard let image else { return }
        ctx.clip(to: rect.standardized)
        image.draw(
            in: CGRect(origin: .zero, size: imageSize),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }

    /// 四角・楕円（塗り → 線の順に描く）
    private static func drawShape(_ path: CGPath, fill: FillStyle, color: RGBAColor, in ctx: CGContext) {
        switch fill {
        case .none:
            break
        case .translucent:
            ctx.setFillColor(color.nsColor.withAlphaComponent(0.25).cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        case .solid:
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// 文字マーカー（行ごとの四角に、蛍光ペン・下線・取り消し線・囲み）
    private static func drawTextMark(_ rects: [CGRect], style: TextMarkStyle, color: RGBAColor, lineWidth: CGFloat, in ctx: CGContext) {
        guard !rects.isEmpty else { return }
        // 線の端・色などを、あとに描く文字（文字に付けるマーカーのとき）に残さない
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let kind = style.kind
        ctx.setLineCap(.butt)
        switch kind {
        case .highlight:
            // 蛍光ペンと同じ塗り方（下の文字が透けて読める）
            let path = CGMutablePath()
            for rect in rects {
                let r = TextMarkGeometry.highlightRect(rect, padding: style.padding)
                let radius = min(r.height * 0.15, r.width / 2)
                path.addRoundedRect(in: r, cornerWidth: radius, cornerHeight: radius)
            }
            ctx.setFillColor(color.cgColor)
            ctx.saveGState()
            ctx.setBlendMode(.multiply)
            ctx.setAlpha(0.9)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.saveGState()
            ctx.setAlpha(0.22)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        case .underline, .strikethrough:
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            for rect in rects {
                let y = kind == .underline
                    ? TextMarkGeometry.underlineY(rect, lineWidth: lineWidth, position: style.linePosition)
                    : TextMarkGeometry.strikethroughY(rect, position: style.linePosition)
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            ctx.strokePath()
        case .box:
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(lineWidth)
            for rect in rects {
                let r = TextMarkGeometry.boxRect(rect, lineWidth: lineWidth, padding: style.padding)
                let radius = min(6, r.height * 0.25)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            }
            ctx.strokePath()
        }
    }

    /// 蛍光ペン。明るい背景では下の文字を残したまま色を付け（乗算）、暗い背景でも見えるよう少しだけ普通に重ねる
    private static func drawHighlight(_ points: [CGPoint], color: RGBAColor, lineWidth: CGFloat, in ctx: CGContext) {
        guard let first = points.first else { return }
        let path = CGMutablePath()
        if points.count == 1 {
            path.move(to: first)
            path.addLine(to: first)
        } else {
            path.addLines(between: points)
        }
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(color.cgColor)

        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        ctx.setAlpha(0.9)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setAlpha(0.22)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// 番号（丸・白抜き・四角・数字だけ）
    private static func drawCounter(
        _ number: Int,
        center: CGPoint,
        radius: CGFloat,
        style: CounterStyle,
        color: RGBAColor,
        in ctx: CGContext
    ) {
        let label = style.format.text(for: number) as NSString
        let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let contrast = color.isLight ? NSColor.black : NSColor.white
        var textColor = contrast
        var fontScale: CGFloat = label.length >= 2 ? 0.95 : 1.15

        switch style.design {
        case .filledCircle:
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: box)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(max(1.5, radius * 0.12))
            ctx.strokeEllipse(in: box.insetBy(dx: radius * 0.06, dy: radius * 0.06))
        case .outlineCircle:
            let ring = max(2, radius * 0.16)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: box)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(ring)
            ctx.strokeEllipse(in: box.insetBy(dx: ring / 2, dy: ring / 2))
            textColor = color.isLight && color != .yellow ? .black : color.nsColor
        case .filledSquare:
            let corner = radius * 0.35
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil))
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            let inner = box.insetBy(dx: radius * 0.06, dy: radius * 0.06)
            ctx.addPath(CGPath(roundedRect: inner, cornerWidth: corner * 0.85, cornerHeight: corner * 0.85, transform: nil))
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(max(1.5, radius * 0.12))
            ctx.strokePath()
        case .plain:
            textColor = color.nsColor
            fontScale = label.length >= 2 ? 1.4 : 1.7
        }

        // フォントを選んでいれば、その太字にする（なければ、数字の幅がそろうシステムのフォント）
        let font = style.fontFamily.flatMap { Annotation.font(family: $0, size: radius * fontScale) }
            ?? NSFont.monospacedDigitSystemFont(ofSize: radius * fontScale, weight: .heavy)
        if style.design == .plain {
            // 数字だけのときは、背景に埋もれないよう縁取りする
            let outline: [NSAttributedString.Key: Any] = [
                .font: font,
                .strokeColor: color.isLight ? NSColor.black : NSColor.white,
                .strokeWidth: 18,
            ]
            let size = label.size(withAttributes: outline)
            ctx.setLineJoin(.round)
            label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: outline)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = label.size(withAttributes: attributes)
        label.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }

    /// 文字（部分ごとの大きさ・枠線・ラベル）
    private static func drawText(
        _ runs: [TextRun],
        origin: CGPoint,
        width: CGFloat?,
        style: TextStyle,
        color: RGBAColor,
        in ctx: CGContext
    ) {
        let maxSize = Annotation.maxFontSize(runs)
        var fillColor = color.nsColor
        let decoration = style.decoration
        // 文字に付けるマーカー（蛍光ペンは文字の後ろ、ほかは文字の上に描く）
        let markerLines = style.marker == nil ? [] : Annotation.textLineRects(runs, origin: origin, width: width, family: style.fontFamily)
        drawTextMarker(markerLines, style: style, textColor: color, fontSize: maxSize, behindText: true, in: ctx)
        defer { drawTextMarker(markerLines, style: style, textColor: color, fontSize: maxSize, behindText: false, in: ctx) }

        switch decoration {
        case .none:
            break
        case .whiteOutline, .blackOutline:
            // 先に太い縁を描き、その上に文字を重ねる
            let outlineColor: NSColor = decoration == .whiteOutline ? .white : .black
            let outlined = NSMutableAttributedString(attributedString: Annotation.attributedText(runs, color: color.nsColor, family: style.fontFamily))
            let full = NSRange(location: 0, length: outlined.length)
            outlined.addAttribute(.strokeColor, value: outlineColor, range: full)
            outlined.addAttribute(.strokeWidth, value: style.outline.strokePercent, range: full)
            ctx.saveGState()
            ctx.setLineJoin(.round)
            draw(outlined, at: origin, width: width)
            ctx.restoreGState()
        case .label:
            // 文字の色の角丸の背景に、見やすい色の文字を載せる
            let size = Annotation.textSize(runs, width: width, family: style.fontFamily)
            let padding = Annotation.labelPadding(fontSize: maxSize)
            let box = CGRect(origin: origin, size: size).insetBy(dx: -padding.width, dy: -padding.height)
            let corner = min(box.height / 2, maxSize * 0.35)
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil))
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
            fillColor = color.isLight ? .black : .white
        }

        draw(Annotation.attributedText(runs, color: fillColor, family: style.fontFamily), at: origin, width: width)
    }

    /// 文字に付けるマーカーを、文字の行ごとに描く（文字マーカーと同じ描き方。色は文字の不透明度に合わせる）。
    /// behindText: 文字の後ろに描くもの（蛍光ペン）か、文字の上に描くもの（下線・取り消し線・囲み）か
    private static func drawTextMarker(_ lines: [CGRect], style: TextStyle, textColor: RGBAColor, fontSize: CGFloat, behindText: Bool, in ctx: CGContext) {
        guard let kind = style.marker, (kind == .highlight) == behindText else { return }
        drawTextMark(
            lines,
            style: TextMarkStyle(kind: kind),
            color: style.resolvedMarkerColor.withAlpha(textColor.a),
            lineWidth: Annotation.textMarkerLineWidth(fontSize: fontSize),
            in: ctx
        )
    }

    /// 文字を描く。width があれば、その幅で折り返す（入力欄と同じ所で行が分かれる）
    private static func draw(_ text: NSAttributedString, at origin: CGPoint, width: CGFloat?) {
        guard let width else {
            text.draw(at: origin)
            return
        }
        text.draw(
            with: CGRect(origin: origin, size: CGSize(width: width, height: .greatestFiniteMagnitude)),
            options: Annotation.wrappingOptions,
            context: nil
        )
    }

    /// 矢印（始点・終点のそれぞれに、三角か山形の矢じり。どちらもなければ線）
    private static func drawArrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat, style: ArrowStyle, in ctx: CGContext) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }

        let angle = atan2(dy, dx)
        let headCount = (style.startHead ? 1 : 0) + (style.endHead ? 1 : 0)
        let headLength = min(length / CGFloat(max(headCount, 1)), style.head.length(lineWidth: lineWidth))
        let spread = CGFloat.pi / 7

        func head(at tip: CGPoint, angle: CGFloat) -> (left: CGPoint, right: CGPoint, base: CGPoint) {
            let left = CGPoint(x: tip.x - headLength * cos(angle - spread), y: tip.y - headLength * sin(angle - spread))
            let right = CGPoint(x: tip.x - headLength * cos(angle + spread), y: tip.y - headLength * sin(angle + spread))
            let base = CGPoint(x: tip.x - headLength * 0.8 * cos(angle), y: tip.y - headLength * 0.8 * sin(angle))
            return (left, right, base)
        }

        let end = head(at: to, angle: angle)
        let start = head(at: from, angle: angle + .pi)
        let filled = style.shape == .filled

        // 三角の矢じりのときは、線を矢じりの付け根で止める（先端が丸くはみ出さないように）
        ctx.beginPath()
        ctx.move(to: style.startHead && filled ? start.base : from)
        ctx.addLine(to: style.endHead && filled ? end.base : to)
        ctx.strokePath()

        var heads: [(CGPoint, (left: CGPoint, right: CGPoint, base: CGPoint))] = []
        if style.endHead { heads.append((to, end)) }
        if style.startHead { heads.append((from, start)) }
        for (tip, h) in heads {
            ctx.beginPath()
            if filled {
                ctx.move(to: tip)
                ctx.addLine(to: h.left)
                ctx.addLine(to: h.right)
                ctx.closePath()
                ctx.fillPath()
            } else {
                // 山形（くの字）
                ctx.move(to: h.left)
                ctx.addLine(to: tip)
                ctx.addLine(to: h.right)
                ctx.strokePath()
            }
        }
    }
}
