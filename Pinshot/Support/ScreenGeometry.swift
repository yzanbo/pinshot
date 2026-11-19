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

    /// rect（AppKit のスクリーン座標）と重なる画面。orMain なら、見つからないときはメインの画面
    static func screen(intersecting rect: NSRect, orMain: Bool = true) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) } ?? (orMain ? NSScreen.main : nil)
    }
}
