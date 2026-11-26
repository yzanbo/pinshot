// README に載せる絵（いちばん上の静止画と、使い方の GIF）を作る（make readme-images が動かす）。
//
// Pinshot の部品（範囲を選ぶ画面・下のバー・浮かせた画像・ツールバー・録画の枠と操作パネル・浮かせた録画）は、
// アプリと同じコードで実際に画面に出し、その中身を描き写して、見本の画面の上に重ねる。
// 見本の画面（架空の分析ダッシュボード）は stage.html を WebKit で描き、マウスのカーソルは絵として描く。
// 自分の画面・個人の情報は写さない。マウス・キーボードの操作も、画面の収録もしない
// （操作は、部品にマウス・キーの知らせを直接渡して動かす）。作っている間、画面に Pinshot の部品が少しのあいだ出る。
//
// 使い方: ReadmeImages <書き出すフォルダ>
//   - hero.png: いちばん上の静止画（書き込みを終えて浮かんでいる画像と操作バー。2 倍の細かさのまま書き出す）
//   - capture.gif: ⌘⇧2 → 範囲をドラッグ → その場に浮かぶ → ドラッグで動かす
//   - edit.gif: ダブルクリックで編集モード → モザイク → 番号 → 文字 → 矢印 → コピー → 編集を終える
//   - record.gif: ⌘⇧2 → 下のバーで「録画」 → 範囲をドラッグ → 録画中の枠と操作パネル → 停止 → 浮かせて再生
import AppKit
import AVFoundation
import AVKit
import SwiftUI
import WebKit

let outputFolder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images", isDirectory: true)
/// 見本の画面（make を動かすリポジトリのいちばん上からの場所）
let stageHTML = URL(fileURLWithPath: "scripts/readme-images/stage.html")

/// 描くときの倍率（Retina と同じ 2 倍で描き、GIF は軽くするため 1 倍に縮めて書き出す）
let renderScale: CGFloat = 2
/// GIF の 1 秒あたりのコマの数
let framesPerSecond: Double = 15
/// 1 コマの秒数
let frameDuration = 1 / framesPerSecond

enum ReadmeImagesError: Error, CustomStringConvertible {
    case pageFailed(String)
    case captureFailed(String)
    case writeFailed(String)

    var description: String {
        switch self {
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
    /// Pinstage の README の絵と同じ大きさ（GIF は 980 × 700、hero.png は 2 倍の 1960 × 1400）。README では幅 800 で見せる
    static let size = CGSize(width: 980, height: 700)
    /// 窓の上の帯（タイトルバー）の高さ
    static let titleBarHeight: CGFloat = 28

    static var screen: NSScreen { NSScreen.main ?? NSScreen.screens[0] }

    /// スクリーン座標（左下が原点）の範囲。画面の真ん中に置く
    static var frame: CGRect {
        let s = screen.frame
        return CGRect(x: (s.midX - size.width / 2).rounded(), y: (s.midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }

    /// 見本の窓の左上からの位置（ポイント、下へ行くほど大きい）を、スクリーン座標にする
    static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX + x, y: frame.maxY - y)
    }

    /// 部品をドラッグで囲むときの、始めと終わりの点（部品の外側に margin の余白をとる。スクリーン座標）
    static func dragPoints(around element: CGRect, margin: CGFloat = 6) -> (start: CGPoint, end: CGPoint) {
        let area = element.insetBy(dx: -margin, dy: -margin)
        return (point(area.minX, area.minY), point(area.maxX, area.maxY))
    }
}

// MARK: - 見本のページ（WebKit で描く）

/// ページの状態（stage.html の setState に渡す）
struct PageState {
    var progress: Double = 0
    /// "idle"（待機中）・"running"（作成中）・"done"（できました）
    var status = "idle"
    var visitors = 128
}

@MainActor
final class SamplePage: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    /// ページを入れておく窓（WebKit が描くには窓に入れておく必要があるので、画面の外に置く）
    let window: NSWindow
    private var loaded: CheckedContinuation<Void, Error>?
    private var cache: [String: CGImage] = [:]

    static var contentSize: CGSize { CGSize(width: Stage.size.width, height: Stage.size.height - Stage.titleBarHeight) }

    override init() {
        let size = Self.contentSize
        webView = WKWebView(frame: NSRect(origin: .zero, size: size))
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        window.orderFrontRegardless()
        webView.navigationDelegate = self
    }

    func load() async throws {
        guard FileManager.default.fileExists(atPath: stageHTML.path) else { throw ReadmeImagesError.pageFailed("stage.html not found") }
        try await withCheckedThrowingContinuation { continuation in
            loaded = continuation
            webView.loadFileURL(stageHTML, allowingReadAccessTo: stageHTML.deletingLastPathComponent())
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finishLoading(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishLoading(error) }
    }

    private func finishLoading(_ error: Error?) {
        if let error { loaded?.resume(throwing: error) } else { loaded?.resume() }
        loaded = nil
    }

    /// ページの中で CSS の selector に当てはまる部品の範囲（ページの上から順。見本の窓の左上からの位置。ポイント。上の帯の分を足す）。
    /// ドラッグする範囲・押す場所・書き込む場所を、決め打ちの座標ではなくページから測る（ページの見た目や画面の大きさを変えても、ずれないように）。
    /// textOnly なら、部品の枠ではなく中の文字の範囲を測る（見出しのように、枠が横幅いっぱいに広がる部品で、文字の右を知りたいとき）
    func frames(of selector: String, textOnly: Bool = false) async throws -> [CGRect] {
        let measure = textOnly
            ? "{ const range = document.createRange(); range.selectNodeContents(e); return range.getBoundingClientRect(); }"
            : "e.getBoundingClientRect()"
        let script = "Array.from(document.querySelectorAll('\(selector)')).flatMap(e => { const r = (() => \(measure))(); return [r.left, r.top, r.width, r.height]; })"
        guard let values = try await webView.evaluateJavaScript(script) as? [Double], !values.isEmpty, values.count % 4 == 0 else {
            throw ReadmeImagesError.pageFailed("no element \(selector)")
        }
        return stride(from: 0, to: values.count, by: 4).map {
            CGRect(x: values[$0], y: values[$0 + 1] + Stage.titleBarHeight, width: values[$0 + 2], height: values[$0 + 3])
        }
    }

    /// ページの中の id の部品の範囲（frames(of:) の 1 つだけのもの）
    func frame(ofElement id: String) async throws -> CGRect {
        try await frames(of: "#\(id)")[0]
    }

    /// state のときのページを、renderScale 倍の画像にする（同じ状態は使い回す）
    func image(_ state: PageState) async throws -> CGImage {
        let key = "\(state.progress)-\(state.status)-\(state.visitors)"
        if let image = cache[key] { return image }
        _ = try await webView.evaluateJavaScript("setState({progress: \(state.progress), status: '\(state.status)', visitors: \(state.visitors)})")
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        let snapshot = try await webView.takeSnapshot(configuration: configuration)
        let size = Self.contentSize
        guard let context = makeContext(size) else { throw ReadmeImagesError.pageFailed("context") }
        drawWithAppKit(in: context) { snapshot.draw(in: CGRect(origin: .zero, size: size)) }
        guard let image = context.makeImage() else { throw ReadmeImagesError.pageFailed("image") }
        cache[key] = image
        return image
    }
}

// MARK: - 画像の土台

/// 画素の大きさを指定した描き場（左下が原点）
func bitmapContext(width: Int, height: Int) -> CGContext? {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
}

/// size（ポイント）の、renderScale 倍の画素の描き場（左下が原点、ポイントで描ける）
func makeContext(_ size: CGSize) -> CGContext? {
    guard let context = bitmapContext(width: Int((size.width * renderScale).rounded()), height: Int((size.height * renderScale).rounded())) else { return nil }
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

/// 0xRRGGBB の色
func color(_ hex: Int, alpha: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha).cgColor
}

/// 画面全体の背景（デスクトップの上に、見本の窓を置いたもの）。範囲を選ぶ画面に「撮った画面」として渡す
@MainActor
func screenImage(page: CGImage) -> CGImage? {
    let screenFrame = Stage.screen.frame
    guard let context = makeContext(screenFrame.size) else { return nil }
    // デスクトップ（落ち着いた色のグラデーション）
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x6B7A9E), color(0x9E8FB3)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: screenFrame.width, y: screenFrame.height), options: [])

    // 見本の窓（影 → 中身の順に描く）
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
    context.draw(page, in: CGRect(x: window.minX, y: window.minY, width: window.width, height: window.height - Stage.titleBarHeight))
    // タイトルバー（信号の 3 つの丸と、ページの名前）
    let titleBar = CGRect(x: window.minX, y: window.maxY - Stage.titleBarHeight, width: window.width, height: Stage.titleBarHeight)
    context.setFillColor(color(0xEDEDF0))
    context.fill(titleBar)
    context.setFillColor(color(0xD1D1D6))
    context.fill(CGRect(x: titleBar.minX, y: titleBar.minY, width: titleBar.width, height: 1))
    for (index, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        context.setFillColor(color(hex))
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
    /// 窓を重ねたあとに描くもの（浮かせた録画の動画の中身。動画は描き写せないので、ここで描く）
    var afterWindows: ((CGContext, CGRect) -> Void)?

    init(excluding windows: [NSWindow]) {
        excluded = Set(windows.map(\.windowNumber))
    }

    /// 奥から手前の順の、出ている窓
    private var visibleWindows: [NSWindow] {
        NSWindow.windowNumbers(options: [])?.reversed().compactMap { number -> NSWindow? in
            guard !excluded.contains(number.intValue), let window = NSApp.window(withWindowNumber: number.intValue),
                  window.isVisible, window.alphaValue > 0.01 else { return nil }
            return window
        } ?? []
    }

    /// background: 画面全体の背景。includesWindows: Pinshot の窓も重ねるか（録画した中身を作るときは重ねない）。
    /// area: 切り出す範囲（スクリーン座標。省くと見本の窓の範囲）
    func frame(background: CGImage, overlay: Overlay?, includesWindows: Bool = true, area: CGRect? = nil) -> CGImage? {
        let area = area ?? Stage.frame
        guard let context = makeContext(area.size) else { return nil }
        let screenFrame = Stage.screen.frame
        context.draw(background, in: screenFrame.offsetBy(dx: -area.minX, dy: -area.minY))
        if includesWindows {
            for window in visibleWindows {
                guard let view = window.contentView, let image = capture(view) else { continue }
                context.saveGState()
                context.setAlpha(window.alphaValue)
                if window.hasShadow {
                    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 16, color: NSColor.black.withAlphaComponent(0.3).cgColor)
                }
                context.draw(image, in: window.frame.offsetBy(dx: -area.minX, dy: -area.minY))
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
        let origin = CGPoint(x: overlay.mouse.x - area.minX - cursor.hotSpot.x,
                             y: overlay.mouse.y - area.minY - (image.size.height - cursor.hotSpot.y))
        drawWithAppKit(in: context) { image.draw(in: CGRect(origin: origin, size: image.size)) }

        // 押したキー（右上に、キーの形で出す）
        guard let keys = overlay.keys else { return }
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
        drawWithAppKit(in: context) { text.draw(at: CGPoint(x: box.minX + 14, y: box.minY + 7)) }
    }
}

// MARK: - マウス・キーの知らせ（部品に直接渡す）

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
func keyEvent(_ characters: String, keyCode: UInt16, in window: NSWindow) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
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

/// 少し待つ（窓を出したあと、SwiftUI が並べ終えるまで）
@MainActor
func settle(_ milliseconds: Int = 40) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
}

// MARK: - 書き出す

struct GIFFrame {
    let image: CGImage
    /// このコマを見せる秒数
    let delay: Double
}

/// 録画した中身の 1 コマ
struct RecordedFrame {
    let image: CGImage
    let time: Double
}

func downscale(_ image: CGImage, by factor: Int) -> CGImage {
    let width = image.width / factor
    let height = image.height / factor
    guard let context = bitmapContext(width: width, height: height) else { return image }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
}

/// 静止画を PNG で書き出す（GIF と違い、描いた倍率のまま。README では幅を指定して小さく見せるので、Retina でもくっきり出る）
func writePNG(_ image: CGImage, named name: String) throws {
    let url = outputFolder.appendingPathComponent(name)
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw ReadmeImagesError.writeFailed(name)
    }
    try data.write(to: url)
    print("wrote \(url.path)")
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

/// 録画した中身を、動画のファイルにする（浮かせた録画に読み込ませる）
func writeMovie(_ frames: [RecordedFrame], size: CGSize, to url: URL) async throws {
    try? FileManager.default.removeItem(at: url)
    // H.264 は縦横が偶数でないと書けない
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

// MARK: - Pinshot の部品を出す

/// 範囲を選ぶ画面（SelectionController と同じ並び。撮った画面の上に、範囲を選ぶビューと下のバー）
@MainActor
struct SelectionScreen {
    let window: NSWindow
    let view: SelectionView
    let options: CaptureOptions
    let bar: NSView

    init(background: CGImage, mode: CaptureMode, mouse: CGPoint) {
        let screen = Stage.screen
        options = CaptureOptions(mode: mode, timer: 0)
        window = SelectionWindow(screen: screen)
        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let imageView = NSImageView(frame: container.bounds)
        imageView.image = NSImage(cgImage: background, size: screen.frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        container.addSubview(imageView)
        view = SelectionView(shot: ScreenShot(screen: screen, image: background), windows: [], options: options)
        view.frame = container.bounds
        container.addSubview(view)
        bar = FirstMouseHostingView(rootView: CaptureModeBar(options: options, audioPicker: RecordingAudioPicker(), cancel: {}))
        bar.frame.size = bar.fittingSize
        // 実際は画面のいちばん下（下から 56 ポイント）に出る。GIF は見本の窓の範囲を切り出すので、窓の下のほうに出す
        let stageBottom = Stage.frame.minY - screen.frame.minY
        bar.frame.origin = NSPoint(x: ((container.bounds.width - bar.frame.width) / 2).rounded(), y: stageBottom + 40)
        container.addSubview(bar)
        container.wantsLayer = true
        window.contentView = container
        window.backgroundColor = .clear
        window.orderFrontRegardless()
        view.updatePointer(screenPoint: mouse)
    }

    /// 下のバーの「録画」のボタンの真ん中（バーの横の真ん中、上から 4 割のあたり。スクリーン座標）
    var recordButton: CGPoint {
        let frame = window.convertToScreen(bar.convert(bar.bounds, to: nil))
        return CGPoint(x: frame.minX + frame.width * 0.5, y: frame.maxY - frame.height * 0.39)
    }

    func movePointer(to point: CGPoint) {
        view.updatePointer(screenPoint: point)
    }

    func mouse(_ type: NSEvent.EventType, at point: CGPoint) {
        let event = mouseEvent(type, at: point, in: window)
        switch type {
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        default: view.mouseUp(with: event)
        }
    }

    func close() {
        window.orderOut(nil)
    }
}

/// 録画中の、赤い点線の枠と操作パネル（RecordingController と同じ並び。録画そのものはしない）
@MainActor
struct RecordingChrome {
    let outline: NSWindow
    let panel: NSPanel
    let model = RecordingPanelModel()

    init(around rect: CGRect) {
        outline = CaptureOutline.show(around: rect)
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
        self.panel = panel
    }

    /// 操作パネルの「停止」のボタンの真ん中（パネルの左から 6 割弱のあたり。スクリーン座標）
    var stopButton: CGPoint {
        CGPoint(x: panel.frame.minX + panel.frame.width * 0.57, y: panel.frame.midY)
    }

    func close() {
        outline.orderOut(nil)
        panel.orderOut(nil)
    }
}

/// 浮かせた録画の窓の中の、動画のビュー
@MainActor
func findPlayerView(in view: NSView) -> NSView? {
    if view is AVPlayerView { return view }
    return view.subviews.lazy.compactMap { findPlayerView(in: $0) }.first
}

// MARK: - 見本を作る

@MainActor
final class ReadmeImages {
    /// どの場面も、ここからカーソルを動かし始める
    static let startPoint = CGPoint(x: 560, y: 380)

    let page = SamplePage()
    var frames: [GIFFrame] = []
    var background: CGImage!
    var compositor: Compositor!
    var overlay = Overlay(mouse: Stage.point(startPoint.x, startPoint.y))
    /// キャプチャの場面で浮かせ、書き込みの場面で使う画像
    var pin: PinController?
    /// 浮かせた画像を、撮った場所から動かした量（スクリーン座標）。書き込みの場面で、ページで測った位置を画像の上の位置に直すのに使う
    var pinOffset = CGPoint.zero

    func run() async throws {
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        try await page.load()
        compositor = Compositor(excluding: [page.window])
        try await makeCapture()
        try await makeEdit()
        pin?.close()
        pin = nil
        await settle(200)
        try await makeRecord()
    }

    func setPage(_ state: PageState) async throws {
        guard let screen = screenImage(page: try await page.image(state)) else { throw ReadmeImagesError.pageFailed("screen") }
        background = screen
    }

    /// 場面の初めに、カーソルを決まった所に戻す
    func resetOverlay() {
        overlay = Overlay(mouse: Stage.point(Self.startPoint.x, Self.startPoint.y))
    }

    /// いまの画面を 1 コマ足す（hold: そのコマを見せる秒数）
    func snap(hold: Double = frameDuration) async {
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

    /// キーを押したことを、右上に出しながら hold 秒見せる
    func showKeys(_ keys: String, hold: Double, _ action: () -> Void) async {
        overlay.keys = keys
        action()
        await snap(hold: hold)
        overlay.keys = nil
    }

    func flush(_ name: String) throws {
        try writeGIF(frames, named: name)
        frames = []
    }

    /// ⌘⇧2 で範囲を選ぶ画面を出す
    func openSelection(mode: CaptureMode) async -> SelectionScreen {
        var selection: SelectionScreen!
        await showKeys("⌘⇧2", hold: 0.5) {
            selection = SelectionScreen(background: background, mode: mode, mouse: overlay.mouse)
            overlay.cursor = .crosshair
        }
        return selection
    }

    /// 範囲を選ぶ画面で、start から end までドラッグして選ぶ
    func dragSelection(_ selection: SelectionScreen, from start: CGPoint, to end: CGPoint, seconds: Double) async -> CaptureTarget? {
        overlay.cursor = .crosshair
        await move(to: start, seconds: 0.4) { selection.movePointer(to: $0) }
        var target: CaptureTarget?
        selection.view.onSelect = { target = $0 }
        selection.mouse(.leftMouseDown, at: start)
        await move(to: end, seconds: seconds) { selection.mouse(.leftMouseDragged, at: $0) }
        await snap(hold: 0.2)
        selection.mouse(.leftMouseUp, at: end)
        selection.close()
        return target
    }

    // MARK: キャプチャ

    func makeCapture() async throws {
        try await setPage(PageState())
        resetOverlay()
        await snap(hold: 0.8)
        // ⌘⇧2 → 表（最近の申し込み）をドラッグで選ぶ。囲む範囲は、ページの部品の位置から測る
        let table = Stage.dragPoints(around: try await page.frame(ofElement: "signups"))
        await move(to: CGPoint(x: table.start.x + 10, y: table.start.y + 5), seconds: 0.7)
        let selection = await openSelection(mode: .region)
        let target = await dragSelection(selection, from: table.start, to: table.end, seconds: 1.0)
        guard case .region(_, let rect) = target else { throw ReadmeImagesError.captureFailed("no region") }

        // その場に浮かぶ
        let pin = try makePin(rect: rect)
        overlay.cursor = .arrow
        pin.canvas.showHUD("コピーしました")
        await snap(hold: 1.2)

        // ドラッグで左上へ動かす
        overlay.cursor = .openHand
        let grab = CGPoint(x: rect.midX, y: rect.midY)
        await move(to: grab, seconds: 0.4)
        overlay.cursor = .closedHand
        let origin = pin.panel.frame.origin
        pinOffset = CGPoint(x: -360, y: 80)
        for offset in path(from: .zero, to: pinOffset, seconds: 0.9) {
            pin.panel.setFrameOrigin(CGPoint(x: origin.x + offset.x, y: origin.y + offset.y))
            overlay.mouse = CGPoint(x: grab.x + offset.x, y: grab.y + offset.y)
            await snap()
        }
        overlay.cursor = .openHand
        await snap(hold: 1.6)
        try flush("capture.gif")
        self.pin = pin
    }

    /// 範囲 rect（スクリーン座標）を撮った画像を、その場に浮かせる（CaptureController と同じく、撮った画面から切り抜く）
    func makePin(rect: CGRect) throws -> PinController {
        guard let cropped = ScreenCapturer.crop(ScreenShot(screen: Stage.screen, image: background), to: rect) else {
            throw ReadmeImagesError.captureFailed("crop")
        }
        let pin = PinController(image: cropped.image, imageSize: cropped.size, frame: rect)
        pin.panel.contentView?.wantsLayer = true
        pin.show()
        return pin
    }

    // MARK: 書き込み

    func makeEdit() async throws {
        guard let pin else { throw ReadmeImagesError.captureFailed("no pin") }
        let window = pin.panel
        let canvas = pin.canvas
        // 見本の窓の左上からの位置（ページで測ったもの）を、動かした画像の上のスクリーン座標にする
        func onPin(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let point = Stage.point(x, y)
            return CGPoint(x: point.x + pinOffset.x, y: point.y + pinOffset.y)
        }
        // 書き込む場所は、表（最近の申し込み）の部品の位置から決める（画面の大きさを変えても、ずれないように）
        let card = try await page.frame(ofElement: "signups")
        // 見出しは横幅いっぱいの部品なので、文字の範囲を測る
        let title = try await page.frames(of: "#signups h2", textOnly: true)[0]
        let mails = try await page.frames(of: "#signups td.mail").reduce(CGRect.null) { $0.union($1) }
        let pros = try await page.frames(of: "#signups .plan.pro")
        func send(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1) {
            let event = mouseEvent(type, at: point, in: window, clickCount: clicks)
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        func press(_ key: String, keyCode: UInt16) async {
            await showKeys(key.uppercased(), hold: 0.45) { canvas.keyDown(with: keyEvent(key, keyCode: keyCode, in: window)) }
        }
        func click(_ point: CGPoint) async {
            await move(to: point, seconds: 0.35)
            send(.leftMouseDown, point)
            send(.leftMouseUp, point)
            await snap(hold: 0.25)
        }
        func drag(from start: CGPoint, to end: CGPoint, seconds: Double) async {
            await move(to: start, seconds: 0.4)
            send(.leftMouseDown, start)
            await move(to: end, seconds: seconds) { send(.leftMouseDragged, $0) }
            send(.leftMouseUp, end)
            await snap(hold: 0.5)
        }

        overlay.cursor = .arrow
        overlay.mouse = onPin(card.midX, card.midY + 40)
        await snap(hold: 0.8)

        // ダブルクリックで編集モード
        let center = onPin(card.midX, card.midY)
        await move(to: center, seconds: 0.4)
        send(.leftMouseDown, center)
        send(.leftMouseUp, center)
        send(.leftMouseDown, center, clicks: 2)
        send(.leftMouseUp, center, clicks: 2)
        await snap(hold: 0.9)

        // M: モザイクでメールアドレス（表のメールの欄すべて）を隠す
        overlay.cursor = .crosshair
        await press("m", keyCode: 46)
        await drag(from: onPin(mails.minX - 4, mails.minY + 2), to: onPin(mails.maxX + 4, mails.maxY - 2), seconds: 0.7)

        // N: Pro の行に番号（Pro のバッジの右）
        await press("n", keyCode: 45)
        for pro in pros {
            await click(onPin(pro.maxX + 16, pro.midY))
        }
        await snap(hold: 0.3)

        // T: 文字（表の見出しの右。1 文字ずつ入れる）
        await press("t", keyCode: 17)
        overlay.cursor = .iBeam
        await click(onPin(title.maxX + 40, title.minY - 6))
        for character in "Pro プラン" {
            (window.firstResponder as? NSTextView)?.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            await snap(hold: 0.09)
        }
        canvas.commitPendingText()
        await snap(hold: 0.4)

        // A: 矢印（文字の右下から、1 つ目の Pro のバッジへ）
        overlay.cursor = .crosshair
        await press("a", keyCode: 0)
        await drag(from: onPin(title.maxX + 110, title.maxY + 4), to: onPin(pros[0].midX, pros[0].minY - 3), seconds: 0.5)

        // ⌘C でコピー（クリップボードには入れず、知らせだけ出す） → ⌘E で編集を終える
        overlay.cursor = .arrow
        await showKeys("⌘C", hold: 1.0) { canvas.showHUD("コピーしました") }
        await showKeys("⌘E", hold: 0.6) { pin.setEditing(false) }
        await snap(hold: 1.6)
        try flush("edit.gif")

        // いちばん上の静止画：書き込みを終えて浮かんでいる画像と操作バー。
        // 「編集を終えました」の知らせ（0.9 秒出て 0.3 秒で消える）が消えてから撮る。カーソルは見本の範囲の外へ出して写さない
        await settle(1500)
        var still = overlay
        still.mouse = CGPoint(x: -10_000, y: -10_000)
        guard let hero = compositor.frame(background: background, overlay: still) else { throw ReadmeImagesError.captureFailed("hero") }
        try writePNG(hero, named: "hero.png")
    }

    // MARK: 録画

    func makeRecord() async throws {
        var state = PageState()
        try await setPage(state)
        resetOverlay()
        await snap(hold: 0.8)

        // ⌘⇧2 → 下のバーの「録画」
        let selection = await openSelection(mode: .region)
        overlay.cursor = .arrow
        await move(to: selection.recordButton, seconds: 0.6) { selection.movePointer(to: $0) }
        overlay.cursor = .pointingHand
        await snap(hold: 0.2)
        selection.options.mode = .record
        await snap(hold: 0.6)

        // グラフ（曜日ごとの訪問数）の範囲をドラッグ。囲む範囲・押すボタンは、ページの部品の位置から測る
        let chart = Stage.dragPoints(around: try await page.frame(ofElement: "chart"))
        let makeButton = try await page.frame(ofElement: "make")
        let target = await dragSelection(selection, from: chart.start, to: chart.end, seconds: 0.9)
        guard case .record(_, let rect) = target else { throw ReadmeImagesError.captureFailed("no record target") }

        // 録画中。録画した中身（枠と操作パネルは写さない。カーソルは写る）も、コマごとに残す
        let chrome = RecordingChrome(around: rect)
        var recorded: [RecordedFrame] = []
        overlay.cursor = .arrow
        func tick() async throws {
            chrome.model.elapsed += frameDuration
            if chrome.model.elapsed > 0.35 { chrome.model.isReady = true }
            try await setPage(state)
            if chrome.model.isReady, let image = compositor.frame(background: background, overlay: overlay, includesWindows: false, area: rect) {
                recorded.append(RecordedFrame(image: image, time: Double(recorded.count) * frameDuration))
            }
            await snap()
        }
        /// 録画しながら、カーソルを target へ動かして押す
        func pressWhileRecording(_ target: CGPoint, seconds: Double) async throws {
            for point in path(from: overlay.mouse, to: target, seconds: seconds) {
                overlay.mouse = point
                try await tick()
            }
            overlay.cursor = .pointingHand
            try await tick()
        }
        for _ in 0..<8 { try await tick() }

        // 「レポートを作成」を押すと、進み具合が伸びて「できました」になる
        try await pressWhileRecording(Stage.point(makeButton.midX, makeButton.midY), seconds: 0.6)
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
        try await pressWhileRecording(chrome.stopButton, seconds: 0.6)
        chrome.close()

        // 止めると、録画がその場に浮かんで再生される
        try await showPlayer(recorded, around: rect)
        try flush("record.gif")
    }

    /// 録画した中身を浮かせて、再生しているところを seconds 秒見せる（RecordingPlayer を使う）
    func showPlayer(_ recorded: [RecordedFrame], around rect: CGRect, seconds: Double = 3.2) async throws {
        let movie = FileManager.default.temporaryDirectory.appendingPathComponent("Pinshot-README-recording.mov")
        try await writeMovie(recorded, size: rect.size, to: movie)
        RecordingPlayer.show(url: movie, pointSize: rect.size, around: rect, on: Stage.screen)
        await settle(300)
        guard let player = NSApp.windows.first(where: { $0.isVisible && $0.contentView.flatMap(findPlayerView) != nil }),
              let video = player.contentView.flatMap(findPlayerView), !recorded.isEmpty else {
            throw ReadmeImagesError.captureFailed("no player")
        }
        var playhead = 0
        // 動画のビューは描き写すと黒くなるので、その範囲を録画した中身で覆う
        compositor.afterWindows = { context, area in
            let frame = player.convertToScreen(video.convert(video.bounds, to: nil)).offsetBy(dx: -area.minX, dy: -area.minY)
            context.draw(recorded[playhead % recorded.count].image, in: frame.insetBy(dx: -0.5, dy: -0.5))
        }
        overlay.cursor = .arrow
        overlay.mouse = CGPoint(x: overlay.mouse.x + 40, y: overlay.mouse.y - 60)
        for _ in 0..<Int(seconds * framesPerSecond) {
            playhead += 1
            await snap()
        }
        compositor.afterWindows = nil
        player.close()
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
