import AppKit

/// キャプチャ中のカーソル。macOS 標準のスクリーンショット（⌘⇧4）と同じカーソルを使う。
/// システムの中の部品を読み込み、見つからないときはふつうの十字・指のカーソルにする
@MainActor
enum CaptureCursors {
    private static let directory = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors"

    /// 範囲を選ぶときの十字（真ん中に小さな丸）
    static let selection: NSCursor = load("screenshotselection", fallbackHotSpot: NSPoint(x: 15, y: 15)) ?? .crosshair

    /// ウィンドウを選ぶときのカメラ
    static let window: NSCursor = load("screenshotwindow", fallbackHotSpot: NSPoint(x: 14, y: 11)) ?? .pointingHand

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
