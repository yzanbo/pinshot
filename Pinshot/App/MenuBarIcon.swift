import AppKit

/// メニューバーのアイコン（カメラのファインダー。1 色のテンプレート画像なので、メニューバーの明るさや押したときに合わせて、macOS が色を付ける）
///
/// 新しい版があるときは、右下を丸く切り抜き、下向きの矢印を抜いた丸を置いたものに替える（Pin シリーズ共通の印）。
/// 色は付けない（メニューバーの色付きの点は、マイク・カメラの使用中の印と紛れやすい）。見慣れた形が欠けるので、小さな点より気づきやすい。
/// どちらも同じ大きさの画像にして、替えてもカメラの位置が動かないようにする。
@MainActor
enum MenuBarIcon {
    /// ふだんのアイコン
    static let normal = make(accessibilityDescription: "Pinshot", withUpdateBadge: false)
    /// 新しい版があるときのアイコン
    static let withUpdateBadge = make(accessibilityDescription: "Pinshot（新しいバージョンがあります）", withUpdateBadge: true)

    /// 画像の大きさ（Pin シリーズの印と同じ 18pt。カメラの絵は、この真ん中に元の大きさのまま置く）
    private static let size = NSSize(width: 18, height: 18)

    private static func make(accessibilityDescription: String, withUpdateBadge: Bool) -> NSImage? {
        guard let camera = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil) else { return nil }
        let image = NSImage(size: size, flipped: false) { rect in
            let origin = NSPoint(x: rect.midX - camera.size.width / 2, y: rect.midY - camera.size.height / 2)
            camera.draw(in: NSRect(origin: origin, size: camera.size))
            if withUpdateBadge, let context = NSGraphicsContext.current?.cgContext {
                drawUpdateBadge(in: context, rect: rect)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// 右下の丸と矢印を描く（大きさは 18pt の画像のときの値。左下が原点）
    ///
    /// 形は Pinshelf の印と同じ。Pinshelf は丸を直径 10pt にして矢印を 1.2 倍にしているが、Pinshot でそうするとカメラのレンズが欠けるので、
    /// 矢印をもとの寸法のまま、丸を直径 8.4pt にする（PNG に書き出して、実寸と拡大で見比べて決めた）
    private static func drawUpdateBadge(in context: CGContext, rect: CGRect) {
        let unit = rect.width / 18
        /// 丸の中心の、右下の角からの距離
        let inset: CGFloat = 4.2
        /// 切り抜く半径（丸の半径より 1.1 大きくして、カメラの絵とのあいだにすき間を作る）
        let cutoutRadius: CGFloat = 5.3
        /// 丸の半径
        let dotRadius: CGFloat = 4.2
        /// 矢印の倍率（下の矢印の座標と線の太さに掛ける）
        let arrow: CGFloat = 1.0
        let center = CGPoint(x: rect.maxX - inset * unit, y: rect.minY + inset * unit)
        func circle(radius: CGFloat) -> CGRect {
            CGRect(x: center.x - radius * unit, y: center.y - radius * unit, width: radius * 2 * unit, height: radius * 2 * unit)
        }
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: center.x + dx * arrow * unit, y: center.y + dy * arrow * unit)
        }
        // 丸の周りを切り抜く
        context.setBlendMode(.clear)
        context.fillEllipse(in: circle(radius: cutoutRadius))
        // 丸（テンプレート画像なので、色は何でもよい。macOS が形だけを使って色を付ける）
        context.setBlendMode(.normal)
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: circle(radius: dotRadius))
        // 下向きの矢印を、丸から抜く
        context.setBlendMode(.clear)
        context.setLineWidth(1.4 * arrow * unit)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let tip = point(0, -2.0)
        context.move(to: point(0, 2.3))
        context.addLine(to: tip)
        context.move(to: point(-1.9, -0.1))
        context.addLine(to: tip)
        context.addLine(to: point(1.9, -0.1))
        context.strokePath()
    }
}
