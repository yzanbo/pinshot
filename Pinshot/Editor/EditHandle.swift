import Foundation

/// 描いたあとに形を直すつまみ
enum EditHandle: Equatable {
    case arrowStart
    case arrowEnd
    /// 四角の角・辺（どの辺を動かすか）
    case rect(ResizeEdges)
}

extension Annotation {
    /// 四角い範囲で表せる書き込みの範囲（四角・楕円・モザイク・ぼかし・スポットライト・文字マーカー）。
    /// 文字マーカーは、行ごとの四角をまとめた範囲（つまみで、文字との位置を手で直せるように）
    var editableRect: CGRect? {
        switch shape {
        case .rectangle(let rect, _), .ellipse(let rect, _), .mosaic(let rect), .blur(let rect), .spotlight(let rect):
            return rect.standardized
        case .textMark(let rects, _):
            let union = rects.reduce(CGRect.null) { $0.union($1) }
            return union.isNull ? nil : union
        default:
            return nil
        }
    }

    func withEditableRect(_ rect: CGRect) -> Annotation {
        var copy = self
        switch shape {
        case .rectangle(_, let style): copy.shape = .rectangle(rect, style: style)
        case .ellipse(_, let style): copy.shape = .ellipse(rect, style: style)
        case .mosaic: copy.shape = .mosaic(rect)
        case .blur: copy.shape = .blur(rect)
        case .spotlight: copy.shape = .spotlight(rect)
        case .textMark(let rects, let style):
            // 行ごとの四角を、まとめた範囲の伸び縮みに合わせて動かす（1 行ならその四角がそのまま rect になる）
            guard let old = editableRect, old.width > 0, old.height > 0 else { break }
            let sx = rect.width / old.width
            let sy = rect.height / old.height
            copy.shape = .textMark(rects.map { r in
                CGRect(
                    x: rect.minX + (r.minX - old.minX) * sx,
                    y: rect.minY + (r.minY - old.minY) * sy,
                    width: r.width * sx,
                    height: r.height * sy
                )
            }, style: style)
        default: break
        }
        return copy
    }

    /// つまみと、その位置（画像の座標）
    var editHandles: [(EditHandle, CGPoint)] {
        if case .arrow(let from, let to, _) = shape {
            return [(.arrowStart, from), (.arrowEnd, to)]
        }
        guard let r = editableRect else { return [] }
        return [
            (.rect([.top, .left]), CGPoint(x: r.minX, y: r.minY)),
            (.rect(.top), CGPoint(x: r.midX, y: r.minY)),
            (.rect([.top, .right]), CGPoint(x: r.maxX, y: r.minY)),
            (.rect(.right), CGPoint(x: r.maxX, y: r.midY)),
            (.rect([.bottom, .right]), CGPoint(x: r.maxX, y: r.maxY)),
            (.rect(.bottom), CGPoint(x: r.midX, y: r.maxY)),
            (.rect([.bottom, .left]), CGPoint(x: r.minX, y: r.maxY)),
            (.rect(.left), CGPoint(x: r.minX, y: r.midY)),
        ]
    }
}
