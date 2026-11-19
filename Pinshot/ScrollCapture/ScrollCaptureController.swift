import AppKit

/// スクロールキャプチャを始める入口（同時に 1 つだけ）
@MainActor
final class ScrollCaptureController {
    static let shared = ScrollCaptureController()

    private var session: ScrollCaptureSession?

    var isRunning: Bool { session != nil }

    /// window があれば前に出してから撮る。scrollPoint は、スクロール操作を送る場所（範囲の中でクリックした場所）
    func start(screen: NSScreen, rect: NSRect, window: WindowInfo? = nil, scrollPoint: NSPoint? = nil) {
        guard session == nil else { return }
        let session = ScrollCaptureSession(screen: screen, rect: rect, window: window, scrollPoint: scrollPoint) { [weak self] result in
            self?.session = nil
            guard let result else { return }
            PinManager.shared.pinScrollCapture(image: result.image, pointSize: result.pointSize, sourceRect: rect, screen: screen)
        }
        self.session = session
        session.start()
    }
}
