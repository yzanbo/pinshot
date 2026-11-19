import Foundation

/// 描いたあとに形を直すつまみ
enum EditHandle: Equatable {
    case arrowStart
    case arrowEnd
    /// 四角の角・辺（どの辺を動かすか）
    case rect(ResizeEdges)
}

extension Annotation {
    /// 四角い範囲で表せる書き込みの範囲（四角・楕円・モザイク・ぼかし・スポットライト）
    var editableRect: CGRect? {
        switch shape {
        case .rectangle(let rect, _), .ellipse(let rect, _), .mosaic(let rect), .blur(let rect), .spotlight(let rect):
            return rect.standardized
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
