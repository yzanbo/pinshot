// README に載せる動き（GIF）を作る（make readme-images が動かす）。
//
// Pinshot の部品（範囲を選ぶ画面・下のバー・浮かせた画像・ツールバー・録画の枠と操作パネル・浮かせた録画）は、
// アプリと同じコードで実際に画面に出し、その中身を描き写して、見本の画面の上に重ねる。
// 見本の画面（架空の分析ダッシュボード）は stage.html を WebKit で描き、マウスのカーソルは絵として描く。
// 自分の画面・個人の情報は写さない。マウス・キーボードの操作も、画面の収録もしない
// （操作は、部品にマウスの知らせを直接渡して動かす）。作っている間、画面に Pinshot の部品が少しのあいだ出る。
//
// 使い方: ReadmeImages <書き出すフォルダ>
//   - capture.gif: ⌘⇧2 → 範囲をドラッグ → その場に浮かぶ → ドラッグで動かす
//   - edit.gif: ダブルクリックで編集モード → モザイク → 番号 → 文字 → 矢印 → コピー → 編集を終える
//   - record.gif: ⌘⇧2 → 下のバーで「録画」 → 範囲をドラッグ → 録画中の枠と操作パネル → 停止 → 浮かせて再生
import AppKit
import AVFoundation
import AVKit
import SwiftUI
import WebKit

let arguments = CommandLine.arguments
let outputFolder = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "docs/images", isDirectory: true)
/// 見本の画面（make を動かすリポジトリのいちばん上からの場所）
let stageHTML = URL(fileURLWithPath: "scripts/readme-images/stage.html")

/// 描くときの倍率（Retina と同じ 2 倍で描き、GIF は軽くするため 1 倍に縮めて書き出す）
let renderScale: CGFloat = 2
/// GIF の 1 秒あたりのコマの数
let framesPerSecond: Double = 15

enum ReadmeImagesError: Error, CustomStringConvertible {
    case noScreen
    case pageFailed(String)
    case captureFailed(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .noScreen: "No screen"
        case .pageFailed(let detail): "Could not draw the sample page: \(detail)"
        case .captureFailed(let detail): "Could not capture: \(detail)"
        case .writeFailed(let name): "Could not write \(name)"
        }
    }
}

// MARK: - 見本の画面を置く場所

/// 見本の窓（ブラウザの窓に見立てる）を置く、画面の範囲。GIF はこの範囲を切り出す
@MainActor
enum Stage {
    static let size = CGSize(width: 1100, height: 720)
    /// 窓の上の帯（タイトルバー）の高さ
    static let titleBarHeight: CGFloat = 28

    static var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    /// スクリーン座標（左下が原点）の範囲。画面の真ん中に置く
    static var frame: CGRect {
        let s = screen.frame
        return CGRect(
            x: (s.midX - size.width / 2).rounded(),
            y: (s.midY - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }

    /// 見本の窓の左上からの位置（ポイント、下へ行くほど大きい）を、スクリーン座標にする
    static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX + x, y: frame.maxY - y)
    }

    /// 見本の窓の左上からの範囲を、スクリーン座標にする
    static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: frame.minX + x, y: frame.maxY - y - height, width: width, height: height)
    }
}

// MARK: - 見本のページ（WebKit で描く）

/// ページの状態（stage.html の setState に渡す）
struct PageState: Equatable {
    var progress: Double = 0
    var status = "idle"
    var visitors = 128
}

@MainActor
final class SamplePage: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let window: NSWindow
    private var loaded: CheckedContinuation<Void, Error>?
    private var cache: [String: CGImage] = [:]

    static var contentSize: CGSize { CGSize(width: Stage.size.width, height: Stage.size.height - Stage.titleBarHeight) }

    override init() {
        let size = Self.contentSize
        webView = WKWebView(frame: NSRect(origin: .zero, size: size))
        // 画面の外に置く（WebKit が描くには窓に入れておく必要がある）
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        window.orderFrontRegardless()
        webView.navigationDelegate = self
    }

    var pageWindow: NSWindow { window }

    func load() async throws {
        guard FileManager.default.fileExists(atPath: stageHTML.path) else { throw ReadmeImagesError.pageFailed("stage.html not found") }
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.loadFileURL(stageHTML, allowingReadAccessTo: stageHTML.deletingLastPathComponent())
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            loaded?.resume()
            loaded = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            loaded?.resume(throwing: error)
            loaded = nil
        }
    }

    /// state のときのページを、renderScale 倍の画像にする（同じ状態は使い回す）
    func image(_ state: PageState) async throws -> CGImage {
        let key = "\(state.progress)-\(state.status)-\(state.visitors)"
        if let image = cache[key] { return image }
        let script = "setState({progress: \(state.progress), status: '\(state.status)', visitors: \(state.visitors)})"
        _ = try await webView.evaluateJavaScript(script)
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        let snapshot = try await webView.takeSnapshot(configuration: configuration)
        let size = Self.contentSize
        guard let context = makeContext(size) else { throw ReadmeImagesError.pageFailed("context") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        snapshot.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = context.makeImage() else { throw ReadmeImagesError.pageFailed("image") }
        cache[key] = image
        return image
    }
}

// MARK: - 画像の土台

/// size（ポイント）の、renderScale 倍の画素の描き場（左下が原点、ポイントで描ける）
func makeContext(_ size: CGSize) -> CGContext? {
    guard let context = CGContext(
        data: nil,
        width: Int((size.width * renderScale).rounded()),
        height: Int((size.height * renderScale).rounded()),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.scaleBy(x: renderScale, y: renderScale)
    context.interpolationQuality = .high
    return context
}

/// AppKit で描く（左下が原点）
func drawWithAppKit(in context: CGContext, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

/// 画面全体の背景（デスクトップの上に、見本の窓を置いたもの）。範囲を選ぶ画面に「撮った画面」として渡す
@MainActor
func screenImage(page: CGImage) -> CGImage? {
    let screenFrame = Stage.screen.frame
    guard let context = makeContext(screenFrame.size) else { return nil }
    // デスクトップ（落ち着いた色のグラデーション）
    let colors = [NSColor(srgbRed: 0.42, green: 0.48, blue: 0.62, alpha: 1).cgColor, NSColor(srgbRed: 0.62, green: 0.56, blue: 0.70, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: screenFrame.width, y: screenFrame.height), options: [])

    // 見本の窓
    let window = Stage.frame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    let windowPath = CGPath(roundedRect: window, cornerWidth: 10, cornerHeight: 10, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(windowPath)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(windowPath)
    context.clip()
    // ページ
    context.draw(page, in: CGRect(x: window.minX, y: window.minY, width: window.width, height: window.height - Stage.titleBarHeight))
    // タイトルバー
    let titleBar = CGRect(x: window.minX, y: window.maxY - Stage.titleBarHeight, width: window.width, height: Stage.titleBarHeight)
    context.setFillColor(NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1).cgColor)
    context.fill(titleBar)
    context.setFillColor(NSColor(srgbRed: 0.82, green: 0.82, blue: 0.84, alpha: 1).cgColor)
    context.fill(CGRect(x: titleBar.minX, y: titleBar.minY, width: titleBar.width, height: 1))
    for (index, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        context.setFillColor(NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: titleBar.minX + 12 + CGFloat(index) * 20, y: titleBar.midY - 6, width: 12, height: 12))
    }
    drawWithAppKit(in: context) {
        let title = NSAttributedString(string: "Hikari Analytics", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(white: 0.25, alpha: 1),
        ])
        title.draw(at: CGPoint(x: titleBar.minX + 80, y: titleBar.midY - title.size().height / 2))
    }
    context.restoreGState()
    return context.makeImage()
}

// MARK: - Pinshot の窓を描き写す

/// ビューを、中身ごと描き写す（renderScale 倍の画素）
func capture(_ view: NSView) -> CGImage? {
    let size = view.bounds.size
    guard size.width > 0, size.height > 0 else { return nil }
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    if let layer = view.layer, let context = makeContext(size) {
        if view.isFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        return context.makeImage()
    }
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage
}

/// マウスのカーソル（絵として描く）
@MainActor
enum Cursor {
    case arrow
    case crosshair
    case pointingHand
    case openHand
    case closedHand
    case iBeam

    var nsCursor: NSCursor {
        switch self {
        case .arrow: .arrow
        case .crosshair: CaptureCursors.selection
        case .pointingHand: .pointingHand
        case .openHand: .openHand
        case .closedHand: .closedHand
        case .iBeam: .iBeam
        }
    }
}

/// 1 コマに重ねるもの
struct Overlay {
    var cursor: Cursor = .arrow
    /// カーソルの位置（スクリーン座標）
    var mouse: CGPoint
    /// 押したキーの表示（例: 「⌘⇧2」）
    var keys: String?
}

/// 画面に出ている Pinshot の窓を、手前の順に重ねて、見本の範囲を 1 コマにする
@MainActor
final class Compositor {
    private let excluded: Set<Int>

    init(excluding windows: [NSWindow]) {
        excluded = Set(windows.map(\.windowNumber))
    }

    /// 奥から手前の順の、出ている窓
    var visibleWindows: [NSWindow] {
        NSWindow.windowNumbers(options: [])?.reversed().compactMap { number -> NSWindow? in
            guard !excluded.contains(number.intValue), let window = NSApp.window(withWindowNumber: number.intValue),
                  window.isVisible, window.alphaValue > 0.01 else { return nil }
            return window
        } ?? []
    }

    /// background: 画面全体の背景。includesWindows: Pinshot の窓も重ねるか（録画した中身を作るときは重ねない）
    /// 窓を重ねたあとに描くもの（浮かせた録画の動画の中身。動画は描き写せないので、ここで描く）
    var afterWindows: ((CGContext, CGRect) -> Void)?

    func frame(background: CGImage, overlay: Overlay?, includesWindows: Bool = true, area: CGRect? = nil) -> CGImage? {
        let area = area ?? Stage.frame
        guard let context = makeContext(area.size) else { return nil }
        let screenFrame = Stage.screen.frame
        context.draw(background, in: CGRect(x: screenFrame.minX - area.minX, y: screenFrame.minY - area.minY,
                                            width: screenFrame.width, height: screenFrame.height))
        if includesWindows {
            for window in visibleWindows {
                guard let view = window.contentView, let image = capture(view) else { continue }
                let rect = window.frame.offsetBy(dx: -area.minX, dy: -area.minY)
                context.saveGState()
                context.setAlpha(window.alphaValue)
                if window.hasShadow {
                    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 16, color: NSColor.black.withAlphaComponent(0.3).cgColor)
                }
                context.draw(image, in: rect)
                context.restoreGState()
            }
            afterWindows?(context, area)
        }
        if let overlay {
            draw(overlay, in: context, area: area)
        }
        return context.makeImage()
    }

    private func draw(_ overlay: Overlay, in context: CGContext, area: CGRect) {
        // カーソル（画像の左上からのずれがホットスポット）
        let cursor = overlay.cursor.nsCursor
        let image = cursor.image
        let hotSpot = cursor.hotSpot
        let origin = CGPoint(x: overlay.mouse.x - area.minX - hotSpot.x, y: overlay.mouse.y - area.minY - (image.size.height - hotSpot.y))
        drawWithAppKit(in: context) {
            image.draw(in: CGRect(origin: origin, size: image.size))
        }
        // 押したキー（右上に、キーの形で出す）
        if let keys = overlay.keys {
            let text = NSAttributedString(string: keys, attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: NSColor.white,
            ])
            let size = text.size()
            let box = CGRect(x: area.width - size.width - 44, y: area.height - Stage.titleBarHeight - size.height - 34,
                             width: size.width + 28, height: size.height + 14)
            context.saveGState()
            context.addPath(CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
            context.fillPath()
            context.restoreGState()
            drawWithAppKit(in: context) {
                text.draw(at: CGPoint(x: box.minX + 14, y: box.minY + 7))
            }
        }
    }
}

// MARK: - マウスの知らせ（部品に直接渡す）

@MainActor
func mouseEvent(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow, clickCount: Int = 1) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: window.convertPoint(fromScreen: point),
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: type == .leftMouseUp ? 0 : 1
    )!
}

@MainActor
func keyEvent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    )!
}

// MARK: - 動き

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

/// ゆっくり始まり、ゆっくり止まる
func smooth(_ t: CGFloat) -> CGFloat {
    t * t * (3 - 2 * t)
}

/// a から b へ、seconds 秒かけて動く位置（コマごと）
func path(from a: CGPoint, to b: CGPoint, seconds: Double) -> [CGPoint] {
    let steps = max(1, Int((seconds * framesPerSecond).rounded()))
    return (1...steps).map { lerp(a, b, smooth(CGFloat($0) / CGFloat(steps))) }
}

// MARK: - 書き出す

struct GIFFrame {
    let image: CGImage
    let delay: Double
}

func downscale(_ image: CGImage, by factor: Int) -> CGImage {
    let width = image.width / factor
    let height = image.height / factor
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
}

func writeGIF(_ frames: [GIFFrame], named name: String) throws {
    let url = outputFolder.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
        throw ReadmeImagesError.writeFailed(name)
    }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for frame in frames {
        CGImageDestinationAddImage(destination, downscale(frame.image, by: Int(renderScale)), [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frame.delay,
                kCGImagePropertyGIFUnclampedDelayTime: frame.delay,
            ],
        ] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw ReadmeImagesError.writeFailed(name) }
    print("wrote \(url.path) (\(frames.count) frames)")
}

/// 少し待つ（窓を出したあと、SwiftUI が並べ終えるまで）
@MainActor
func settle(_ milliseconds: Int = 40) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
}

/// 録画した中身を、動画のファイルにする（浮かせた録画に読み込ませる）
func writeMovie(_ frames: [(image: CGImage, time: Double)], size: CGSize, to url: URL) async throws {
    try? FileManager.default.removeItem(at: url)
    let width = Int(size.width * renderScale) / 2 * 2
    let height = Int(size.height * renderScale) / 2 * 2
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in frames {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        guard let pool = adaptor.pixelBufferPool else { break }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { continue }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.draw(frame.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(seconds: frame.time, preferredTimescale: 600))
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw ReadmeImagesError.writeFailed(url.lastPathComponent) }
}

/// 浮かせた録画の窓の中の、動画のビュー
@MainActor
func findPlayerView(in view: NSView) -> NSView? {
    if view is AVPlayerView { return view }
    for subview in view.subviews {
        if let found = findPlayerView(in: subview) { return found }
    }
    return nil
}

// MARK: - 見本を作る

@MainActor
final class ReadmeImages {
    let page = SamplePage()
    var frames: [GIFFrame] = []
    var background: CGImage!
    var compositor: Compositor!
    var overlay = Overlay(mouse: Stage.point(560, 380))

    func run() async throws {
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        try await page.load()
        compositor = Compositor(excluding: [page.pageWindow])
        try await setPage(PageState())
        try await makeCapture()
        try await makeEdit()
        currentPin?.close()
        currentPin = nil
        await settle(200)
        try await makeRecord()
    }

    func setPage(_ state: PageState) async throws {
        let image = try await page.image(state)
        guard let screen = screenImage(page: image) else { throw ReadmeImagesError.pageFailed("screen") }
        background = screen
    }

    /// いまの画面を 1 コマ足す（hold: そのコマを見せる秒数）
    func snap(hold: Double = 1 / framesPerSecond) async {
        await settle(30)
        guard let image = compositor.frame(background: background, overlay: overlay) else { return }
        frames.append(GIFFrame(image: image, delay: hold))
    }

    /// カーソルを動かしながらコマを足す（each: 動かすたびに呼ぶ）
    func move(to target: CGPoint, seconds: Double, each: ((CGPoint) -> Void)? = nil) async {
        for point in path(from: overlay.mouse, to: target, seconds: seconds) {
            overlay.mouse = point
            each?(point)
            await snap()
        }
    }

    func flush(_ name: String) throws {
        try writeGIF(frames, named: name)
        frames = []
    }

    // MARK: キャプチャ

    /// 範囲を選ぶ画面（SelectionController と同じ並び。撮った画面の上に、範囲を選ぶビューと下のバー）
    func showSelection(mode: CaptureMode) -> (window: NSWindow, view: SelectionView, options: CaptureOptions) {
        let screen = Stage.screen
        let shot = ScreenShot(screen: screen, image: background)
        let options = CaptureOptions(mode: mode, timer: 0)
        let window = SelectionWindow(screen: screen)
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let imageView = NSImageView(frame: container.bounds)
        imageView.image = NSImage(cgImage: background, size: screen.frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        container.addSubview(imageView)
        let view = SelectionView(shot: shot, windows: [], options: options)
        view.frame = container.bounds
        container.addSubview(view)
        let bar = FirstMouseHostingView(rootView: CaptureModeBar(options: options, audioPicker: RecordingAudioPicker(), cancel: {}))
        bar.frame.size = bar.fittingSize
        // 実際は画面のいちばん下（下から 56 ポイント）に出る。GIF は見本の窓の範囲を切り出すので、窓の下のほうに出す
        let stageBottom = Stage.frame.minY - screen.frame.minY
        bar.frame.origin = NSPoint(x: ((container.bounds.width - bar.frame.width) / 2).rounded(), y: stageBottom + 40)
        container.addSubview(bar)
        container.wantsLayer = true
        window.contentView = container
        window.backgroundColor = .clear
        window.orderFrontRegardless()
        view.updatePointer(screenPoint: overlay.mouse)
        return (window, view, options)
    }

    func makeCapture() async throws {
        overlay = Overlay(mouse: Stage.point(560, 380))
        await snap(hold: 0.8)
        await move(to: Stage.point(700, 230), seconds: 0.7)

        // ⌘⇧2 で、範囲を選ぶ画面
        overlay.keys = "⌘⇧2"
        let selection = showSelection(mode: .region)
        overlay.cursor = .crosshair
        await snap(hold: 0.5)
        overlay.keys = nil

        // 表をドラッグで選ぶ
        let start = Stage.point(690, 235)
        let end = Stage.point(1084, 539)
        await move(to: start, seconds: 0.4) { selection.view.updatePointer(screenPoint: $0) }
        var target: CaptureTarget?
        selection.view.onSelect = { target = $0 }
        selection.view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, in: selection.window))
        await move(to: end, seconds: 1.0) { point in
            selection.view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: point, in: selection.window))
        }
        await snap(hold: 0.2)
        selection.view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, in: selection.window))
        selection.window.orderOut(nil)
        guard case .region(_, let rect) = target else { throw ReadmeImagesError.captureFailed("no region") }

        // その場に浮かぶ
        let pin = try makePin(rect: rect)
        overlay.cursor = .arrow
        pin.canvas.showHUD("コピーしました")
        await snap(hold: 1.2)

        // ドラッグで左へ動かす
        overlay.cursor = .openHand
        let grab = CGPoint(x: rect.midX, y: rect.midY)
        await move(to: grab, seconds: 0.4)
        overlay.cursor = .closedHand
        let offset = CGPoint(x: -360, y: 80)
        let from = pin.panel.frame.origin
        for (index, point) in path(from: .zero, to: offset, seconds: 0.9).enumerated() {
            _ = index
            pin.panel.setFrameOrigin(CGPoint(x: from.x + point.x, y: from.y + point.y))
            overlay.mouse = CGPoint(x: grab.x + point.x, y: grab.y + point.y)
            await snap()
        }
        overlay.cursor = .openHand
        await snap(hold: 1.6)
        try flush("capture.gif")
        currentPin = pin
    }

    var currentPin: PinController?

    // MARK: 書き込み

    func makeEdit() async throws {
        guard let pin = currentPin else { throw ReadmeImagesError.captureFailed("no pin") }
        let window = pin.panel
        let canvas = pin.canvas
        // 画像の左上からの位置（ポイント）を、スクリーン座標にする
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: window.frame.minX + x, y: window.frame.maxY - y)
        }
        func down(_ point: CGPoint, clicks: Int = 1) { canvas.mouseDown(with: mouseEvent(.leftMouseDown, at: point, in: window, clickCount: clicks)) }
        func drag(_ point: CGPoint) { canvas.mouseDragged(with: mouseEvent(.leftMouseDragged, at: point, in: window)) }
        func up(_ point: CGPoint, clicks: Int = 1) { canvas.mouseUp(with: mouseEvent(.leftMouseUp, at: point, in: window, clickCount: clicks)) }
        func press(_ key: String, _ code: UInt16) async {
            overlay.keys = key.uppercased()
            canvas.keyDown(with: keyEvent(key, keyCode: code, in: window))
            await snap(hold: 0.45)
            overlay.keys = nil
        }
        func click(_ point: CGPoint) async {
            await move(to: point, seconds: 0.35)
            down(point)
            up(point)
            await snap(hold: 0.25)
        }

        overlay.cursor = .arrow
        overlay.mouse = at(200, 200)
        await snap(hold: 0.8)

        // ダブルクリックで編集モード
        let center = at(197, 160)
        await move(to: center, seconds: 0.4)
        down(center); up(center)
        down(center, clicks: 2); up(center, clicks: 2)
        await snap(hold: 0.9)

        // M: モザイクでメールアドレスを隠す
        overlay.cursor = .crosshair
        await press("m", 46)
        let mosaicStart = at(100, 66)
        let mosaicEnd = at(244, 228)
        await move(to: mosaicStart, seconds: 0.4)
        down(mosaicStart)
        await move(to: mosaicEnd, seconds: 0.7) { drag($0) }
        up(mosaicEnd)
        await snap(hold: 0.5)

        // N: Pro の行に番号
        await press("n", 45)
        await click(at(352, 77))
        await click(at(352, 147))
        await snap(hold: 0.3)

        // T: 文字
        await press("t", 17)
        overlay.cursor = .iBeam
        await click(at(150, 6))
        let text = "Pro プラン"
        for index in text.indices {
            if let field = window.firstResponder as? NSTextView {
                field.insertText(String(text[index]), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            await snap(hold: 0.09)
        }
        canvas.commitPendingText()
        await snap(hold: 0.4)

        // A: 矢印
        overlay.cursor = .crosshair
        await press("a", 0)
        let arrowStart = at(258, 28)
        let arrowEnd = at(312, 70)
        await move(to: arrowStart, seconds: 0.4)
        down(arrowStart)
        await move(to: arrowEnd, seconds: 0.5) { drag($0) }
        up(arrowEnd)
        await snap(hold: 0.5)

        // ⌘C でコピー（クリップボードには入れず、知らせだけ出す）
        overlay.cursor = .arrow
        overlay.keys = "⌘C"
        canvas.showHUD("コピーしました")
        await snap(hold: 1.0)
        // ⌘E で編集を終える
        overlay.keys = "⌘E"
        pin.setEditing(false)
        await snap(hold: 0.6)
        overlay.keys = nil
        await snap(hold: 1.6)
        try flush("edit.gif")
    }

    // MARK: 録画

    func makeRecord() async throws {
        var state = PageState()
        try await setPage(state)
        overlay = Overlay(mouse: Stage.point(560, 380))
        await snap(hold: 0.8)

        // ⌘⇧2 → 下のバーの「録画」
        overlay.keys = "⌘⇧2"
        let selection = showSelection(mode: .region)
        overlay.cursor = .crosshair
        await snap(hold: 0.5)
        overlay.keys = nil
        guard let bar = selection.window.contentView?.subviews.last else { throw ReadmeImagesError.captureFailed("no bar") }
        // 「録画」のボタンは、バーの横の真ん中あたり（上から 4 割）
        let barFrame = selection.window.convertToScreen(bar.convert(bar.bounds, to: nil))
        let recordButton = CGPoint(x: barFrame.minX + barFrame.width * 0.5, y: barFrame.maxY - barFrame.height * 0.39)
        overlay.cursor = .arrow
        await move(to: recordButton, seconds: 0.6) { selection.view.updatePointer(screenPoint: $0) }
        overlay.cursor = .pointingHand
        await snap(hold: 0.2)
        selection.options.mode = .record
        await snap(hold: 0.6)

        // グラフの範囲をドラッグ
        overlay.cursor = .crosshair
        let start = Stage.point(22, 241)
        let end = Stage.point(678, 593)
        await move(to: start, seconds: 0.5) { selection.view.updatePointer(screenPoint: $0) }
        var target: CaptureTarget?
        selection.view.onSelect = { target = $0 }
        selection.view.mouseDown(with: mouseEvent(.leftMouseDown, at: start, in: selection.window))
        await move(to: end, seconds: 0.9) { point in
            selection.view.mouseDragged(with: mouseEvent(.leftMouseDragged, at: point, in: selection.window))
        }
        selection.view.mouseUp(with: mouseEvent(.leftMouseUp, at: end, in: selection.window))
        selection.window.orderOut(nil)
        guard case .record(_, let rect) = target else { throw ReadmeImagesError.captureFailed("no record target") }

        // 録画中: 赤い点線の枠と操作パネル（RecordingController と同じ並び）
        let outline = CaptureOutline.show(around: rect)
        let model = RecordingPanelModel()
        let hosting = FirstMouseHostingView(rootView: RecordingPanelView(model: model))
        let size = hosting.fittingSize
        let candidates = [
            NSPoint(x: rect.midX - size.width / 2, y: rect.minY - 12 - size.height),
            NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 12),
        ]
        let origin = ScreenGeometry.firstFittingOrigin(candidates, size: size, in: Stage.screen.visibleFrame)
        let panel = OverlayPanel(contentRect: NSRect(origin: origin, size: size), level: .statusBar)
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.orderFrontRegardless()

        // 録画した中身（枠と操作パネルは写さない。カーソルは写る）
        var recorded: [(image: CGImage, time: Double)] = []
        var elapsed: Double = 0
        let step = 1 / framesPerSecond
        overlay.cursor = .arrow
        func tick() async throws {
            elapsed += step
            model.elapsed = elapsed
            if elapsed > 0.35 { model.isReady = true }
            try await setPage(state)
            if model.isReady, let image = compositor.frame(background: background, overlay: overlay, includesWindows: false, area: rect) {
                recorded.append((image, recorded.last.map { $0.time + step } ?? 0))
            }
            await snap()
        }
        for _ in 0..<8 { try await tick() }

        // 「レポートを作成」を押す
        let button = Stage.point(107, 524)
        for point in path(from: overlay.mouse, to: button, seconds: 0.6) {
            overlay.mouse = point
            try await tick()
        }
        overlay.cursor = .pointingHand
        try await tick()
        state.status = "running"
        let runFrames = Int(2.6 * framesPerSecond)
        for index in 0...runFrames {
            state.progress = (Double(index) / Double(runFrames) * 20).rounded() / 20
            state.visitors = 128 + index / 6
            if index > 6 { overlay.cursor = .arrow }
            try await tick()
        }
        state.status = "done"
        state.progress = 1
        for _ in 0..<10 { try await tick() }

        // 操作パネルの「停止」
        let stopButton = CGPoint(x: panel.frame.minX + panel.frame.width * 0.57, y: panel.frame.midY)
        for point in path(from: overlay.mouse, to: stopButton, seconds: 0.6) {
            overlay.mouse = point
            try await tick()
        }
        overlay.cursor = .pointingHand
        try await tick()
        outline.orderOut(nil)
        panel.orderOut(nil)

        // 止めると、録画がその場に浮かんで再生される
        let movie = FileManager.default.temporaryDirectory.appendingPathComponent("Pinshot-README-recording.mov")
        try await writeMovie(recorded, size: rect.size, to: movie)
        RecordingPlayer.show(url: movie, pointSize: rect.size, around: rect, on: Stage.screen)
        await settle(300)
        let player = NSApp.windows.first { $0.isVisible && $0.contentView.map { findPlayerView(in: $0) != nil } == true }
        var playhead: Double = 0
        compositor.afterWindows = { context, area in
            guard let player, let content = player.contentView, let video = findPlayerView(in: content), !recorded.isEmpty else { return }
            let frame = player.convertToScreen(video.convert(video.bounds, to: nil)).offsetBy(dx: -area.minX, dy: -area.minY)
            let index = Int(playhead * framesPerSecond) % recorded.count
            // 動画のビューは描き写すと黒くなるので、その範囲を録画した中身で覆う
            context.draw(recorded[index].image, in: frame.insetBy(dx: -0.5, dy: -0.5))
        }
        overlay.cursor = .arrow
        overlay.mouse = CGPoint(x: overlay.mouse.x + 40, y: overlay.mouse.y - 60)
        for _ in 0..<Int(3.2 * framesPerSecond) {
            playhead += step
            await snap()
        }
        compositor.afterWindows = nil
        player?.close()
        try flush("record.gif")
    }

    /// 範囲 rect（スクリーン座標）を撮った画像を、その場に浮かせる（CaptureController と同じく、撮った画面から切り抜く）
    func makePin(rect: CGRect) throws -> PinController {
        let shot = ScreenShot(screen: Stage.screen, image: background)
        guard let cropped = ScreenCapturer.crop(shot, to: rect) else { throw ReadmeImagesError.captureFailed("crop") }
        let pin = PinController(image: cropped.image, imageSize: cropped.size, frame: rect)
        pin.panel.contentView?.wantsLayer = true
        pin.show()
        return pin
    }
}

// MARK: - 起動

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    do {
        try await ReadmeImages().run()
        exit(0)
    } catch {
        FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}
app.run()
