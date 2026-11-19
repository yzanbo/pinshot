import AppKit

/// キャプチャ中のカーソル。macOS 標準のスクリーンショット（⌘⇧4）と同じカーソルを使う。
/// システムの中の部品を読み込み、見つからないときはふつうの十字・指のカーソルにする
@MainActor
enum CaptureCursors {
    private static let directory = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors"

    /// 範囲を選ぶときの十字（真ん中に小さな丸）。黒い背景でも見えるよう、1pt の白い縁を付ける
    static let selection: NSCursor = outlined(
        load("screenshotselection", fallbackHotSpot: NSPoint(x: 15, y: 15)) ?? .crosshair
    )

    /// ウィンドウを選ぶときのカメラ
    static let window: NSCursor = load("screenshotwindow", fallbackHotSpot: NSPoint(x: 14, y: 11)) ?? .pointingHand

    /// カーソルの形のまわりに、白い縁を付けたカーソル（縁のぶん、まわりを広げる）
    private static func outlined(_ cursor: NSCursor, width: CGFloat = 1) -> NSCursor {
        let base = cursor.image
        let size = NSSize(width: base.size.width + width * 2, height: base.size.height + width * 2)
        // 形をそのまま白で塗りつぶしたもの
        let silhouette = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        // 白い形を上下左右・斜めにずらして重ね、その上に元の形を描く（Retina でもにじまないよう、描くたびに描き直す）
        let image = NSImage(size: size, flipped: false) { _ in
            let steps: [CGFloat] = [-width, 0, width]
            for dx in steps {
                for dy in steps where dx != 0 || dy != 0 {
                    silhouette.draw(in: NSRect(x: width + dx, y: width + dy, width: base.size.width, height: base.size.height))
                }
            }
            base.draw(in: NSRect(x: width, y: width, width: base.size.width, height: base.size.height))
            return true
        }
        let hotSpot = NSPoint(x: cursor.hotSpot.x + width, y: cursor.hotSpot.y + width)
        return NSCursor(image: image, hotSpot: hotSpot)
    }

    private static func load(_ name: String, fallbackHotSpot: NSPoint) -> NSCursor? {
        let folder = (directory as NSString).appendingPathComponent(name)
        guard let image = NSImage(contentsOfFile: (folder as NSString).appendingPathComponent("cursor.pdf")) else { return nil }
        // カーソルの「指している点」は info.plist に書いてある
        var hotSpot = fallbackHotSpot
        if let info = NSDictionary(contentsOfFile: (folder as NSString).appendingPathComponent("info.plist")),
           let x = info["hotx"] as? Double, let y = info["hoty"] as? Double {
            hotSpot = NSPoint(x: x, y: y)
        }
        return NSCursor(image: image, hotSpot: hotSpot)
    }
}
