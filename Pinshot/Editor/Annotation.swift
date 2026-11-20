import AppKit

/// 1 つの書き込み。座標はすべて「元の画像のポイント座標（左上が原点）」
struct Annotation: Codable, Identifiable, Equatable {
    enum Shape: Codable, Equatable {
        case rectangle(CGRect, style: ShapeStyle)
        case ellipse(CGRect, style: ShapeStyle)
        case arrow(from: CGPoint, to: CGPoint, style: ArrowStyle)
        case pen([CGPoint])
        case highlight([CGPoint])
        /// 文字マーカー。rects は文字の行ごとの範囲（読み取った文字の位置に合わせたもの）
        case textMark([CGRect], style: TextMarkStyle)
        /// width: 折り返す幅（画像のポイント）。nil なら折り返さない（改行したところだけで行を分ける）
        case text(runs: [TextRun], origin: CGPoint, style: TextStyle, width: CGFloat? = nil)
        case counter(Int, center: CGPoint, radius: CGFloat, style: CounterStyle)
        case mosaic(CGRect)
        case blur(CGRect)
        case spotlight(CGRect)
    }

    var id = UUID()
    var shape: Shape
    var color: RGBAColor
    var lineWidth: CGFloat

    var isMosaic: Bool {
        if case .mosaic = shape { return true }
        return false
    }

    var isBlur: Bool {
        if case .blur = shape { return true }
        return false
    }

    var isSpotlight: Bool {
        if case .spotlight = shape { return true }
        return false
    }

    /// 色や太さを持たない書き込み（モザイク・ぼかし・スポットライト）
    var isEffect: Bool { isMosaic || isBlur || isSpotlight }

    var isHighlight: Bool {
        if case .highlight = shape { return true }
        return false
    }

    /// 影を付けない書き込み（蛍光ペン・文字マーカーの蛍光ペン。下の文字と重ねて読ませるもの）
    var isTranslucentMarker: Bool {
        switch shape {
        case .highlight: true
        case .textMark(_, let style): style.kind == .highlight
        default: false
        }
    }

    var isText: Bool {
        if case .text = shape { return true }
        return false
    }

    var counterNumber: Int? {
        if case .counter(let number, _, _, _) = shape { return number }
        return nil
    }

    /// 書き込みに対応するツール（ツールバーのオプションを出し分けるのに使う）
    var tool: Tool {
        switch shape {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .pen: .pen
        case .highlight: .highlight
        case .textMark: .textMark
        case .text: .text
        case .counter: .counter
        case .mosaic: .mosaic
        case .blur: .blur
        case .spotlight: .spotlight
        }
    }

    /// 小さすぎて意味のない書き込みかどうか
    var isMeaningful: Bool {
        switch shape {
        case .rectangle(let rect, _), .ellipse(let rect, _), .mosaic(let rect), .blur(let rect), .spotlight(let rect):
            return rect.width > 2 && rect.height > 2
        case .arrow(let from, let to, _):
            return hypot(to.x - from.x, to.y - from.y) > 4
        case .pen(let points), .highlight(let points):
            return points.count > 1
        case .textMark(let rects, _):
            return rects.contains { $0.width > 2 && $0.height > 2 }
        case .text(let runs, _, _, _):
            return !Annotation.plainText(runs).isEmpty
        case .counter:
            return true
        }
    }
}

extension Annotation {
    /// 文字のフォント。family（フォントのファミリー名）があればその太字（なければふつうの太さ）、
    /// nil か Mac に入っていないときは、システムの太字にする
    static func textFont(size: CGFloat, family: String? = nil) -> NSFont {
        if let family, let font = font(family: family, size: size) { return font }
        return .boldSystemFont(ofSize: size)
    }

    /// family の太字。太字がないフォントは、ふつうの太さにする
    static func font(family: String, size: CGFloat) -> NSFont? {
        let manager = NSFontManager.shared
        let bold = manager.font(withFamily: family, traits: .boldFontMask, weight: 9, size: size)
        if let bold, manager.traits(of: bold).contains(.boldFontMask) { return bold }
        return manager.font(withFamily: family, traits: [], weight: 5, size: size) ?? bold
    }

    /// 折り返して描く・測るときの決まり（入力欄・書き込み・書き出しで同じ所で行が分かれるよう、ここにそろえる）
    static let wrappingOptions: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    /// text を width の幅で折り返したときの大きさ（切り上げ）
    static func wrappedSize(of text: NSAttributedString, width: CGFloat) -> CGSize {
        let rect = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: wrappingOptions)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    static func plainText(_ runs: [TextRun]) -> String {
        runs.map(\.text).joined()
    }

    /// 文字の部分を、表示用の文字列にする（scale は画面の拡大率）
    static func attributedText(_ runs: [TextRun], color: NSColor, scale: CGFloat = 1, family: String? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs {
            result.append(NSAttributedString(string: run.text, attributes: [
                .font: textFont(size: run.fontSize * scale, family: family),
                .foregroundColor: color,
            ]))
        }
        return result
    }

    /// 文字そのものの大きさ（枠線・ラベルの余白は含まない）。width があれば、その幅で折り返したときの大きさ
    static func textSize(_ runs: [TextRun], width: CGFloat? = nil, family: String? = nil) -> CGSize {
        let text = attributedText(runs, color: .black, family: family)
        guard let width else { return text.size() }
        return wrappedSize(of: text, width: width)
    }

    /// 文字のうち、いちばん大きい文字の大きさ
    static func maxFontSize(_ runs: [TextRun]) -> CGFloat {
        runs.map(\.fontSize).max() ?? FontSizes.default
    }

    /// 文字に付けるマーカーの線の太さ（文字の大きさに合わせる）
    static func textMarkerLineWidth(fontSize: CGFloat) -> CGFloat {
        max(1.5, fontSize * 0.07)
    }

    /// 文字の行ごとの、文字の線がある範囲（画像のポイント座標）。文字に付けるマーカーを引く所。
    /// 行の高さ（行間を含む）ではなく、ベースラインから上に文字の大きさの 8 割・下に 1 割にする
    /// （日本語の文字は、行の範囲の下側に余白があり、そのままだと線が下にずれるため）
    static func textLineRects(_ runs: [TextRun], origin: CGPoint, width: CGFloat?, family: String?) -> [CGRect] {
        let text = attributedText(runs, color: .black, family: family)
        guard text.length > 0 else { return [] }
        // 描くとき（NSString の折り返し）と同じ所で行が分かれるよう、行の左右の余白なし・フォントの行間を使う
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        layout.usesFontLeading = true
        let container = NSTextContainer(size: CGSize(width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var rects: [CGRect] = []
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { lineRect, usedRect, _, glyphRange, _ in
            guard usedRect.width > 0.5 else { return }
            // 行の中でいちばん大きい文字（1 つの文字の中で、部分ごとに大きさが違うことがあるため）
            var size: CGFloat = 0
            storage.enumerateAttribute(.font, in: layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)) { value, _, _ in
                size = max(size, (value as? NSFont)?.pointSize ?? 0)
            }
            guard size > 0 else { return }
            let baseline = lineRect.minY + layout.location(forGlyphAt: glyphRange.location).y
            rects.append(CGRect(x: origin.x + usedRect.minX, y: origin.y + baseline - size * 0.8, width: usedRect.width, height: size * 0.9))
        }
        return rects
    }

    /// ラベルの余白
    static func labelPadding(fontSize: CGFloat) -> CGSize {
        CGSize(width: max(4, fontSize * 0.35), height: max(2, fontSize * 0.15))
    }

    /// 書き込みが占める範囲（画像のポイント座標）
    var bounds: CGRect {
        switch shape {
        case .rectangle(let rect, _), .ellipse(let rect, _), .mosaic(let rect), .blur(let rect), .spotlight(let rect):
            return rect.standardized
        case .arrow(let from, let to, let style):
            let head = style.head.length(lineWidth: lineWidth) / 2
            return CGRect(corner: from, to).insetBy(dx: -head, dy: -head)
        case .pen(let points), .highlight(let points):
            guard let first = points.first else { return .zero }
            let box = points.reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
            return isHighlight ? box.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2) : box
        case .text(let runs, let origin, let style, let width):
            let rect = CGRect(origin: origin, size: Annotation.textSize(runs, width: width, family: style.fontFamily))
            let maxSize = Annotation.maxFontSize(runs)
            var box: CGRect
            switch style.decoration {
            case .none:
                box = rect
            case .whiteOutline, .blackOutline:
                let pad = maxSize * style.outline.overflow
                box = rect.insetBy(dx: -pad, dy: -pad)
            case .label:
                let padding = Annotation.labelPadding(fontSize: maxSize)
                box = rect.insetBy(dx: -padding.width, dy: -padding.height)
            }
            // マーカー（囲み・下線など）が文字の外にはみ出すぶんも含める
            if let marker = style.marker {
                let lineWidth = Annotation.textMarkerLineWidth(fontSize: maxSize)
                for line in Annotation.textLineRects(runs, origin: origin, width: width, family: style.fontFamily) {
                    box = box.union(TextMarkGeometry.outer(line, style: TextMarkStyle(kind: marker), lineWidth: lineWidth))
                }
            }
            return box
        case .counter(_, let center, let radius, let style):
            let r = style.design == .plain ? radius * 1.2 : radius
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        case .textMark(let rects, let style):
            return rects
                .map { TextMarkGeometry.outer($0, style: style, lineWidth: lineWidth) }
                .reduce(CGRect.null) { $0.union($1) }
        }
    }

    /// point がこの書き込みに当たっているか。tolerance は当たりとみなす距離（画像のポイント）
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = tolerance + lineWidth / 2
        switch shape {
        case .rectangle(let rect, let style) where style.fill != .none:
            // 塗った四角は中も当たり
            return rect.standardized.insetBy(dx: -reach, dy: -reach).contains(point)
        case .ellipse(let rect, let style) where style.fill != .none:
            let rect = rect.standardized.insetBy(dx: -reach, dy: -reach)
            let dx = (point.x - rect.midX) / max(rect.width / 2, 1)
            let dy = (point.y - rect.midY) / max(rect.height / 2, 1)
            return dx * dx + dy * dy <= 1
        case .rectangle(let rect, _), .spotlight(let rect):
            // 四角・スポットライトは枠の近くだけ当たりにする（中の書き込みを選べるように）
            let rect = rect.standardized
            let outer = rect.insetBy(dx: -reach, dy: -reach)
            let inner = rect.insetBy(dx: reach, dy: reach)
            return outer.contains(point) && !(inner.width > 0 && inner.height > 0 && inner.contains(point))
        case .ellipse(let rect, _):
            // 楕円も線の近くだけ
            let rect = rect.standardized
            let a = max(rect.width / 2, 1)
            let b = max(rect.height / 2, 1)
            let dx = (point.x - rect.midX) / a
            let dy = (point.y - rect.midY) / b
            let r = (dx * dx + dy * dy).squareRoot()
            return abs(r - 1) * min(a, b) <= reach
        case .mosaic, .blur, .text, .counter:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .arrow(let from, let to, _):
            return distance(from: point, toSegment: from, to) <= reach + 2
        case .textMark(let rects, let style):
            return rects.contains {
                TextMarkGeometry.outer($0, style: style, lineWidth: lineWidth).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
            }
        case .pen(let points), .highlight(let points):
            if points.count == 1 { return hypot(point.x - points[0].x, point.y - points[0].y) <= reach }
            return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= reach }
        }
    }

    /// 位置をずらした書き込み
    func translated(by delta: CGVector) -> Annotation {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.dx, y: p.y + delta.dy) }
        func offset(_ r: CGRect) -> CGRect { r.offsetBy(dx: delta.dx, dy: delta.dy) }
        var moved = self
        switch shape {
        case .rectangle(let rect, let style): moved.shape = .rectangle(offset(rect), style: style)
        case .ellipse(let rect, let style): moved.shape = .ellipse(offset(rect), style: style)
        case .mosaic(let rect): moved.shape = .mosaic(offset(rect))
        case .blur(let rect): moved.shape = .blur(offset(rect))
        case .spotlight(let rect): moved.shape = .spotlight(offset(rect))
        case .arrow(let from, let to, let style): moved.shape = .arrow(from: move(from), to: move(to), style: style)
        case .pen(let points): moved.shape = .pen(points.map(move))
        case .highlight(let points): moved.shape = .highlight(points.map(move))
        case .textMark(let rects, let style): moved.shape = .textMark(rects.map(offset), style: style)
        case .text(let runs, let origin, let style, let width): moved.shape = .text(runs: runs, origin: move(origin), style: style, width: width)
        case .counter(let number, let center, let radius, let style):
            moved.shape = .counter(number, center: move(center), radius: radius, style: style)
        }
        return moved
    }

    /// ツールバーの設定（色・太さ・各ツールのオプション）を反映した書き込み
    func restyled(with style: EditorStyle, aspects: StyleAspects = .all, lineWidthTool: Tool? = nil) -> Annotation {
        guard !isEffect else { return self }
        var copy = self
        if aspects.contains(.color) {
            copy.color = style.color.withAlpha(color.a)
        }
        if aspects.contains(.opacity) {
            copy.color = copy.color.withAlpha(style.opacity)
        }
        // 太さは、変えたツールと同じ種類の書き込みにだけ反映する（lineWidthTool が nil ならすべて）
        let appliesWidth = aspects.contains(.lineWidth) && (lineWidthTool == nil || lineWidthTool == tool)
        switch shape {
        case .highlight, .pen:
            if appliesWidth { copy.lineWidth = style.lineWidth(for: tool) }
        case .textMark(let rects, _):
            if appliesWidth { copy.lineWidth = style.lineWidth(for: .textMark) }
            if aspects.contains(.textMark) { copy.shape = .textMark(rects, style: style.textMark) }
        case .rectangle(let rect, _):
            if appliesWidth { copy.lineWidth = style.lineWidth(for: .rectangle) }
            if aspects.contains(.rectangle) { copy.shape = .rectangle(rect, style: style.rectangle) }
        case .ellipse(let rect, _):
            if appliesWidth { copy.lineWidth = style.lineWidth(for: .ellipse) }
            if aspects.contains(.ellipse) { copy.shape = .ellipse(rect, style: style.ellipse) }
        case .arrow(let from, let to, _):
            if appliesWidth { copy.lineWidth = style.lineWidth(for: .arrow) }
            if aspects.contains(.arrow) { copy.shape = .arrow(from: from, to: to, style: style.arrow) }
        case .counter(let number, let center, _, _):
            if aspects.contains(.counter) {
                copy.shape = .counter(number, center: center, radius: style.counterSize.radius, style: style.counter)
            }
        case .text(let runs, let origin, _, let width):
            // 文字の大きさは、文字の大きさの欄で変える（withFontSize）
            if aspects.contains(.text) { copy.shape = .text(runs: runs, origin: origin, style: style.text, width: width) }
        default:
            break
        }
        return copy
    }

    /// いちばん大きい文字が size になるよう、部分ごとの大きさの比率を保って拡大・縮小した書き込み（文字以外は変わらない）
    func withFontSize(_ size: CGFloat) -> Annotation {
        guard case .text(let runs, let origin, let style, let width) = shape else { return self }
        let current = Annotation.maxFontSize(runs)
        guard current > 0, abs(current - size) > 0.01 else { return self }
        let ratio = size / current
        var copy = self
        let scaled = runs.map { run -> TextRun in
            let newSize = ((run.fontSize * ratio) * 2).rounded() / 2
            return TextRun(text: run.text, fontSize: min(max(newSize, FontSizes.range.lowerBound), FontSizes.range.upperBound))
        }
        copy.shape = .text(runs: scaled, origin: origin, style: style, width: width)
        return copy
    }
}

/// 点から線分までの距離
private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

extension CGPoint {
    /// origin から見た向きを 45° ごとにそろえた点（長さは変えない）。shift を押しながら矢印などを描くときに使う
    func snappedTo45(from origin: CGPoint) -> CGPoint {
        let dx = x - origin.x
        let dy = y - origin.y
        let length = hypot(dx, dy)
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: origin.x + length * cos(angle), y: origin.y + length * sin(angle))
    }
}

extension CGRect {
    /// 2 点を対角とする四角形
    init(corner a: CGPoint, _ b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
