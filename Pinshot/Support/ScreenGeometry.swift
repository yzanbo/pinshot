import AppKit

/// 画面の座標の変換と、位置から画面を探す処理。
///
/// AppKit の座標は「メインの画面の左下が原点・上が正」、
/// Quartz（CGWindow・アクセシビリティ・CGEvent）の座標は「メインの画面の左上が原点・下が正」
@MainActor
enum ScreenGeometry {
    /// メインの画面（原点のある画面）の高さ
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// AppKit の点 → Quartz の点
    static func quartzPoint(_ point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Quartz の四角 → AppKit の四角
    static func appKitRect(fromQuartz rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// point（AppKit のスクリーン座標）がある画面。orMain なら、見つからないときはメインの画面
    static func screen(containing point: NSPoint, orMain: Bool = true) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? (orMain ? NSScreen.main : nil)
    }

    /// ツールバーなどの部品を画面の端から離す幅
    nonisolated static let edgeMargin: CGFloat = 4

    /// 幅 width の部品の左端 x を、画面（visible）の左右の中に収める（端から edgeMargin 離す）
    nonisolated static func clampedX(_ x: CGFloat, width: CGFloat, in visible: NSRect) -> CGFloat {
        min(max(x, visible.minX + edgeMargin), visible.maxX - width - edgeMargin)
    }

    /// 画像（frame）の下に、size の部品（ツールバー・操作バー）を置く位置。
    /// 左右は、画像のうち画面（visible）に見えている部分の真ん中にし、画面の中に収める。
    /// 画像の下に余白がないとき（画面の下の方へ動かした・拡大したなど）は、上へは回さず、画面のいちばん下（edgeGap 上）に置く
    nonisolated static func originBelow(_ frame: NSRect, size: NSSize, gap: CGFloat, in visible: NSRect, edgeGap: CGFloat = 8) -> NSPoint {
        let shown = frame.intersection(visible)
        let midX = shown.isNull ? frame.midX : shown.midX
        let x = clampedX(midX - size.width / 2, width: size.width, in: visible)
        let y = max(frame.minY - gap - size.height, visible.minY + edgeGap)
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    /// rect（AppKit のスクリーン座標）と重なる画面。orMain なら、見つからないときはメインの画面
    static func screen(intersecting rect: NSRect, orMain: Bool = true) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) } ?? (orMain ? NSScreen.main : nil)
    }
}
