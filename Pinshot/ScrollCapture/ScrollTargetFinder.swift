import AppKit
import ApplicationServices

/// アクセシビリティの情報から、スクロールできる領域（ブラウザならページの部分）を見つける
@MainActor
enum ScrollTargetFinder {
    private static let scrollRoles: Set<String> = ["AXScrollArea", "AXWebArea"]
    private static let minSize: CGFloat = 80
    /// Web の中身のアクセシビリティ情報を出すよう頼んだアプリ
    private static var webAccessibilityRequested: Set<pid_t> = []
    /// 1 回の問い合わせを待つ長さ（応答しないアプリで、範囲を選ぶ画面が固まらないように）
    private static let messagingTimeout: Float = 0.3
    private static var didSetMessagingTimeout = false
    /// いまの探索の中で、問い合わせが時間切れになったか（なったら、それ以上は聞かない）
    private static var timedOut = false
    /// ウィンドウ全体を探すときに見る要素の数の上限
    private static let searchLimit = 1500

    /// window の中で、point（スクリーン座標）の下にあるスクロール領域（スクリーン座標）。
    /// 見つからなければ、そのウィンドウの中でいちばん大きいスクロール領域。それもなければ nil。
    ///
    /// 自分のアプリ（範囲を選ぶ画面など）が上に重なっていても間違えないよう、
    /// 画面全体ではなく、そのウィンドウのアプリだけに「この位置にあるものは？」と聞く
    static func scrollArea(at point: NSPoint, in window: WindowInfo) -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }
        let pid = window.ownerPID
        guard pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        prepareMessaging()
        enableWebAccessibility(pid: pid)

        let app = AXUIElementCreateApplication(pid)
        let windowFrame = window.frame
        let cgPoint = ScreenGeometry.quartzPoint(point)
        var element: AXUIElement?
        let hit = AXUIElementCopyElementAtPosition(app, Float(cgPoint.x), Float(cgPoint.y), &element)
        if hit == .cannotComplete { timedOut = true }
        if hit == .success, let element, let rect = scrollAncestor(of: element, clippedTo: windowFrame) {
            return rect.integral
        }
        // 応答しないアプリには、それ以上聞かない
        guard !timedOut else { return nil }
        if let axWindow = axWindow(of: app, matching: windowFrame),
           let rect = largestScrollArea(in: axWindow, clippedTo: windowFrame) {
            return rect.integral
        }
        return nil
    }

    /// Chrome などは、頼んでから情報を出すまで少しかかるので、何回か聞き直す
    static func scrollAreaRetrying(at point: NSPoint, in window: WindowInfo, attempts: Int = 6) async -> NSRect? {
        for attempt in 0..<attempts {
            if let rect = scrollArea(at: point, in: window) { return rect }
            if attempt < attempts - 1 {
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        return nil
    }

    /// ウィンドウを前に出す（ほかのウィンドウに隠れていると、そちらにスクロールが送られたり写ったりするため）
    static func raise(_ window: WindowInfo) {
        guard AXIsProcessTrusted() else { return }
        prepareMessaging()
        let app = AXUIElementCreateApplication(window.ownerPID)
        if let axWindow = axWindow(of: app, matching: window.frame) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        }
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: window.ownerPID)?.activate()
    }

    // MARK: - 探す

    /// 親をたどって、いちばん近いスクロール領域を探す
    private static func scrollAncestor(of element: AXUIElement, clippedTo windowFrame: NSRect?) -> NSRect? {
        var current: AXUIElement? = element
        var webArea: NSRect?
        for _ in 0..<40 {
            guard let node = current, !timedOut else { break }
            if let role = Self.string(node, kAXRoleAttribute), scrollRoles.contains(role), var rect = frame(of: node) {
                if let windowFrame { rect = rect.intersection(windowFrame) }
                if rect.width >= minSize, rect.height >= minSize {
                    if role == "AXScrollArea" { return rect }
                    // Web の領域は、外側のスクロール領域が見つからなかったときに使う
                    if webArea == nil { webArea = rect }
                }
            }
            if Self.string(node, kAXRoleAttribute) == (kAXWindowRole as String) { break }
            current = Self.element(node, kAXParentAttribute)
        }
        return webArea
    }

    /// ウィンドウの中で、いちばん大きいスクロール領域
    private static func largestScrollArea(in window: AXUIElement, clippedTo windowFrame: NSRect?) -> NSRect? {
        var best: NSRect?
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        while !queue.isEmpty, visited < searchLimit, !timedOut {
            let (node, depth) = queue.removeFirst()
            visited += 1
            if let role = string(node, kAXRoleAttribute), scrollRoles.contains(role), var rect = frame(of: node) {
                if let windowFrame { rect = rect.intersection(windowFrame) }
                if rect.width >= minSize, rect.height >= minSize,
                   rect.width * rect.height > (best.map { $0.width * $0.height } ?? 0) {
                    best = rect
                }
            }
            guard depth < 12, let children = elements(node, kAXChildrenAttribute) else { continue }
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return best
    }

    /// アプリのウィンドウのうち、位置と大きさが frame（スクリーン座標）と同じもの
    private static func axWindow(of app: AXUIElement, matching windowFrame: NSRect) -> AXUIElement? {
        guard let windows = elements(app, kAXWindowsAttribute) else { return nil }
        let matched = windows.first { window in
            guard let rect = frame(of: window) else { return false }
            return abs(rect.minX - windowFrame.minX) < 4 && abs(rect.minY - windowFrame.minY) < 4
                && abs(rect.width - windowFrame.width) < 4 && abs(rect.height - windowFrame.height) < 4
        }
        return matched ?? windows.first { frame(of: $0)?.intersects(windowFrame) ?? false }
    }

    /// 問い合わせを待つ長さを決め、時間切れの印を消す（探すたびに呼ぶ）。
    /// 待つ長さは、システム全体の要素に設定すると、このアプリのすべての問い合わせに効く
    /// （アプリの要素に設定しても、その子の要素には効かない）
    private static func prepareMessaging() {
        timedOut = false
        guard !didSetMessagingTimeout else { return }
        didSetMessagingTimeout = true
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    /// Chrome や Electron のアプリは、頼まないと Web の中身のアクセシビリティ情報を出さないので、出してもらう
    private static func enableWebAccessibility(pid: pid_t) {
        guard !webAccessibilityRequested.contains(pid) else { return }
        webAccessibilityRequested.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: - アクセシビリティの値を読む

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        guard !timedOut else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if result == .cannotComplete { timedOut = true }
        guard result == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        guard let array = value(element, attribute) as? [AnyObject] else { return nil }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    /// アクセシビリティの位置と大きさ（メインの画面の左上が原点）を、AppKit のスクリーン座標にする
    private static func frame(of element: AXUIElement) -> NSRect? {
        guard
            let positionValue = value(element, kAXPositionAttribute), CFGetTypeID(positionValue) == AXValueGetTypeID(),
            let sizeValue = value(element, kAXSizeAttribute), CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return ScreenGeometry.appKitRect(fromQuartz: CGRect(origin: position, size: size))
    }
}
