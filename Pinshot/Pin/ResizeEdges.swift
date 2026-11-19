import AppKit

/// 画像の端（大きさを変えるときにつかむ場所）
struct ResizeEdges: OptionSet {
    let rawValue: Int
    static let left = ResizeEdges(rawValue: 1 << 0)
    static let right = ResizeEdges(rawValue: 1 << 1)
    static let top = ResizeEdges(rawValue: 1 << 2)
    static let bottom = ResizeEdges(rawValue: 1 << 3)
}

extension ResizeEdges {
    /// 端のドラッグ（dx・dy はスクリーン座標での移動量）から、縦横比を保った新しい幅と、動かさない点を求める
    func resizeTarget(startFrame frame: NSRect, dx: CGFloat, dy: CGFloat) -> (width: CGFloat, anchor: NSPoint) {
        var width = frame.width
        var height = frame.height
        if contains(.right) { width = frame.width + dx }
        if contains(.left) { width = frame.width - dx }
        if contains(.top) { height = frame.height + dy }
        if contains(.bottom) { height = frame.height - dy }

        let aspect = frame.width / max(frame.height, 1)
        let horizontal = contains(.left) || contains(.right)
        let vertical = contains(.top) || contains(.bottom)
        let newWidth: CGFloat
        if horizontal, vertical {
            // 角は、大きく動かしたほうに合わせる
            newWidth = abs(width / frame.width - 1) >= abs(height / frame.height - 1) ? width : height * aspect
        } else if horizontal {
            newWidth = width
        } else {
            newWidth = height * aspect
        }
        let anchor = NSPoint(
            x: contains(.left) ? frame.maxX : (contains(.right) ? frame.minX : frame.midX),
            y: contains(.bottom) ? frame.maxY : (contains(.top) ? frame.minY : frame.midY)
        )
        return (newWidth, anchor)
    }

    /// 端・角に合った、大きさを変えるカーソル
    var cursor: NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch self {
            case [.top, .left]: position = .topLeft
            case [.top, .right]: position = .topRight
            case [.bottom, .left]: position = .bottomLeft
            case [.bottom, .right]: position = .bottomRight
            case .top: position = .top
            case .bottom: position = .bottom
            case .left: position = .left
            default: position = .right
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        if self == .top || self == .bottom { return .resizeUpDown }
        return .resizeLeftRight
    }

    /// view の中の point が、どの端・角の近くか（zone は端からの距離。flipped かどうかで上下を読み替える）
    static func at(_ point: NSPoint, in bounds: NSRect, zone: CGFloat, flipped: Bool) -> ResizeEdges {
        var edges: ResizeEdges = []
        if point.x < bounds.minX + zone { edges.insert(.left) }
        if point.x > bounds.maxX - zone { edges.insert(.right) }
        let nearLow = point.y < bounds.minY + zone
        let nearHigh = point.y > bounds.maxY - zone
        if flipped {
            if nearLow { edges.insert(.top) }
            if nearHigh { edges.insert(.bottom) }
        } else {
            if nearLow { edges.insert(.bottom) }
            if nearHigh { edges.insert(.top) }
        }
        return edges
    }
}

/// 端をつかんで大きさを変えている間の状態（つかんだ端と、つかんだときのウィンドウ・マウスの位置）
struct EdgeResizeDrag {
    let edges: ResizeEdges
    let startFrame: NSRect
    let startMouse: NSPoint

    /// つかんだ端があれば、いまのウィンドウとマウスの位置を覚えて始める
    init?(edges: ResizeEdges, window: NSWindow?) {
        guard !edges.isEmpty, let window else { return nil }
        self.edges = edges
        self.startFrame = window.frame
        self.startMouse = NSEvent.mouseLocation
    }

    /// いまのマウスの位置（スクリーン座標）での、新しい幅と、動かさない点
    func target(mouse: NSPoint = NSEvent.mouseLocation) -> (width: CGFloat, anchor: NSPoint) {
        edges.resizeTarget(startFrame: startFrame, dx: mouse.x - startMouse.x, dy: mouse.y - startMouse.y)
    }
}
