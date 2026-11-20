import AppKit
import ScreenCaptureKit

/// 1 枚の画面と、その画面を撮った画像
struct ScreenShot {
    let screen: NSScreen
    let image: CGImage
}

@MainActor
enum ScreenCapturer {
    /// 画面に出ているものの一覧（許可がないとエラーになる）
    static func shareableContent() async throws -> SCShareableContent {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        ScreenPermission.confirmed = true
        return content
    }

    /// つながっているすべての画面を、そのときの見た目のまま撮る
    /// excluding: 写さないウィンドウ（範囲を選ぶ画面が出るまでかぶせる膜など）
    static func captureAllScreens(content: SCShareableContent, excluding windowIDs: Set<CGWindowID> = []) async throws -> [ScreenShot] {
        var shots: [ScreenShot] = []
        for screen in NSScreen.screens {
            if let shot = try await capture(screen: screen, content: content, excluding: windowIDs) {
                shots.append(shot)
            }
        }
        return shots
    }

    /// 1 枚の画面を撮る
    static func capture(screen: NSScreen, content: SCShareableContent, excluding windowIDs: Set<CGWindowID> = []) async throws -> ScreenShot? {
        guard let display = content.display(for: screen) else { return nil }

        let excluded = content.windows.filter { windowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return ScreenShot(screen: screen, image: image)
    }

    /// ウィンドウだけを撮る（ほかのウィンドウに隠れていても、そのウィンドウの中身が撮れる）。
    /// 戻り値の size はポイント
    static func captureWindow(id: CGWindowID, content: SCShareableContent) async throws -> (image: CGImage, size: CGSize)? {
        guard let window = content.windows.first(where: { $0.windowID == id }) else { return nil }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let rect = filter.contentRect
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(rect.width * scale)
        config.height = Int(rect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, rect.size)
    }

    /// 撮った画面から、rect（スクリーン座標）の部分を切り抜く。戻り値の size はポイント
    static func crop(_ shot: ScreenShot, to rect: NSRect) -> (image: CGImage, size: CGSize)? {
        let screenFrame = shot.screen.frame
        let local = rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY).intersection(
            NSRect(origin: .zero, size: screenFrame.size)
        )
        guard local.width >= 1, local.height >= 1 else { return nil }

        // AppKit（左下が原点）→ 画像（左上が原点）、ポイント → ピクセル
        let scaleX = CGFloat(shot.image.width) / screenFrame.width
        let scaleY = CGFloat(shot.image.height) / screenFrame.height
        let pixelRect = CGRect(
            x: local.minX * scaleX,
            y: (screenFrame.height - local.maxY) * scaleY,
            width: local.width * scaleX,
            height: local.height * scaleY
        ).integral

        guard let image = shot.image.cropping(to: pixelRect) else { return nil }
        return (image, local.size)
    }
}

extension SCShareableContent {
    /// screen にあたる、ScreenCaptureKit のディスプレイ
    func display(for screen: NSScreen) -> SCDisplay? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
        return displays.first { $0.displayID == number }
    }
}
