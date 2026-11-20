import AppKit

/// 画面に出ているウィンドウの一覧（ウィンドウを選んで撮るとき・メニューの一覧に使う）
enum WindowList {
    /// 画面に出ているふつうのウィンドウ（手前から順）
    @MainActor
    static func visibleWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let myPID = Int(ProcessInfo.processInfo.processIdentifier)

        return list.compactMap { info in
            guard
                (info[kCGWindowLayer as String] as? Int) == 0,
                let pid = info[kCGWindowOwnerPID as String] as? Int, pid != myPID,
                let number = info[kCGWindowNumber as String] as? Int,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                bounds.width >= 40, bounds.height >= 40
            else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }

            return WindowInfo(
                id: CGWindowID(number),
                // CGWindow の座標は「メインの画面の左上が原点」なので、AppKit の座標（左下が原点）に直す
                frame: ScreenGeometry.appKitRect(fromQuartz: bounds),
                appName: info[kCGWindowOwnerName as String] as? String ?? "",
                title: info[kCGWindowName as String] as? String ?? "",
                ownerPID: pid_t(pid)
            )
        }
    }
}
