import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// README に載せる見本の画像を作る（書き込み・書き出しは、アプリと同じ描き方を使う）。
/// ふだんのテストでは飛ばす。make readme-images が、書き出す場所を環境変数 PINSHOT_README_IMAGES で渡したときだけ動く
final class ReadmeImages: XCTestCase {
    func testMakeReadmeImages() throws {
        guard let path = ProcessInfo.processInfo.environment["PINSHOT_README_IMAGES"], !path.isEmpty else {
            throw XCTSkip("PINSHOT_README_IMAGES がないので飛ばす（make readme-images で作る）")
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let page = SamplePage()
        let base = try XCTUnwrap(page.image())
        let effects = EffectImages(
            pixelated: ImageEffects.pixelated(base, size: SamplePage.size),
            blurred: ImageEffects.blurred(base, size: SamplePage.size)
        )

        // 書き込みを合成して、余白・背景・角丸・影を付ける（「書き出しの見た目」と同じ）
        func export(_ annotations: [Annotation], background: ExportBackground = .ocean) throws -> CGImage {
            let rendered = try XCTUnwrap(ImageExporter.render(
                base: base, imageSize: SamplePage.size, annotations: annotations, effects: effects
            ))
            var decoration = ExportDecoration()
            decoration.isEnabled = true
            decoration.background = background
            decoration.padding = .medium
            decoration.corner = .small
            decoration.shadow = true
            return try XCTUnwrap(ImageExporter.decorate(rendered, pointSize: SamplePage.size, with: decoration)).image
        }

        let steps = SamplePage.steps
        let pointSize = { (image: CGImage) in CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2) }

        // 1. 書き込みをすべて入れた画像（README の冒頭）
        let hero = try export(steps.flatMap { $0 })
        try writePNG(hero, pointSize: pointSize(hero), to: folder.appendingPathComponent("hero.png"))

        // 2. 書き込みを 1 つずつ足していく GIF（大きさは半分の 1 倍にして、軽くする）
        var frames: [(image: CGImage, delay: Double)] = [(try export([]), 1.2)]
        var shown: [Annotation] = []
        for (index, step) in steps.enumerated() {
            shown += step
            frames.append((try export(shown), index == steps.count - 1 ? 3.5 : 0.9))
        }
        try writeGIF(frames.map { (try XCTUnwrap(halved($0.image)), $0.delay) }, to: folder.appendingPathComponent("annotate.gif"))

        // 3. スポットライト・ぼかしで、見せたいところだけを目立たせる例
        let focus = try export(SamplePage.focus, background: .lavender)
        try writePNG(focus, pointSize: pointSize(focus), to: folder.appendingPathComponent("focus.png"))
    }

    private func writePNG(_ image: CGImage, pointSize: CGSize, to url: URL) throws {
        let data = try XCTUnwrap(ImageExporter.pngData(image, pointSize: pointSize))
        try data.write(to: url)
    }

    /// 縦横を半分にする（Retina の 2 倍の画像を、1 倍にする）
    private func halved(_ image: CGImage) -> CGImage? {
        let width = image.width / 2
        let height = image.height / 2
        guard let ctx = CGContext.makeRGBA(width: width, height: height) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    private func writeGIF(_ frames: [(image: CGImage, delay: Double)], to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil))
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame.image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frame.delay,
                    kCGImagePropertyGIFUnclampedDelayTime: frame.delay,
                ],
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

/// 見本にする、架空のアプリの「プロフィール」設定の画面（名前・メールアドレスは架空のもの）
private struct SamplePage {
    static let size = CGSize(width: 760, height: 500)
    static let scale: CGFloat = 2

    // 書き込みの位置に使う、画面の部品の場所（ポイント。左上が原点）
    static let nameField = CGRect(x: 212, y: 150, width: 330, height: 34)
    static let emailField = CGRect(x: 212, y: 222, width: 330, height: 34)
    static let bioField = CGRect(x: 212, y: 294, width: 500, height: 40)
    static let noteOrigin = CGPoint(x: 212, y: 356)
    static let note = "変更は、次にログインしたときから反映されます。"
    static let cancelButton = CGRect(x: 532, y: 440, width: 96, height: 34)
    static let saveButton = CGRect(x: 640, y: 440, width: 96, height: 34)
    static let avatarCenter = CGPoint(x: 646, y: 196)

    static let bodyFont = NSFont.systemFont(ofSize: 14)
    static let noteFont = NSFont.systemFont(ofSize: 12)

    // MARK: 書き込み

    /// 書き込みを足していく順番（GIF の 1 コマに 1 つの段）
    static var steps: [[Annotation]] {
        let red = RGBAColor.red
        let counter = CounterStyle()
        var label = TextStyle()
        label.decoration = .whiteOutline
        let noteSize = (note as NSString).size(withAttributes: [.font: noteFont])
        let noteRect = CGRect(origin: noteOrigin, size: noteSize)
        return [
            // 1. 名前に番号
            [Annotation(shape: .counter(1, center: CGPoint(x: nameField.maxX + 22, y: nameField.midY), radius: 14, style: counter), color: red, lineWidth: 4)],
            // 2. メールアドレスをモザイクで隠して、番号
            [
                Annotation(shape: .mosaic(emailField.insetBy(dx: 8, dy: 6)), color: red, lineWidth: 4),
                Annotation(shape: .counter(2, center: CGPoint(x: emailField.maxX + 22, y: emailField.midY), radius: 14, style: counter), color: red, lineWidth: 4),
            ],
            // 3. 注意書きに蛍光ペン（文字マーカー）
            [Annotation(shape: .textMark([noteRect], style: TextMarkStyle(kind: .highlight)), color: .yellow, lineWidth: 4)],
            // 4. 保存するボタンを四角で囲む
            [Annotation(shape: .rectangle(saveButton.insetBy(dx: -6, dy: -6), style: ShapeStyle(corner: .small, fill: .none)), color: red, lineWidth: 4)],
            // 5. 番号・文字・矢印で、押すところを示す
            [
                Annotation(shape: .counter(3, center: CGPoint(x: 440, y: 404), radius: 14, style: counter), color: red, lineWidth: 4),
                Annotation(shape: .text(runs: [TextRun(text: "最後にここを押す", fontSize: 20)], origin: CGPoint(x: 462, y: 391), style: label), color: red, lineWidth: 4),
                Annotation(shape: .arrow(from: CGPoint(x: 600, y: 420), to: CGPoint(x: 628, y: 446), style: ArrowStyle()), color: red, lineWidth: 4),
            ],
        ]
    }

    /// スポットライト・ぼかし・ラベルの例
    static var focus: [Annotation] {
        let blue = RGBAColor.blue
        var label = TextStyle()
        label.decoration = .label
        return [
            Annotation(shape: .spotlight(CGRect(x: avatarCenter.x - 66, y: avatarCenter.y - 58, width: 132, height: 128)), color: blue, lineWidth: 4),
            Annotation(shape: .blur(nameField.insetBy(dx: 4, dy: 4)), color: blue, lineWidth: 4),
            Annotation(shape: .blur(emailField.insetBy(dx: 4, dy: 4)), color: blue, lineWidth: 4),
            Annotation(shape: .text(runs: [TextRun(text: "写真はここから変えられます", fontSize: 18)], origin: CGPoint(x: 436, y: 52), style: label), color: blue, lineWidth: 4),
            Annotation(shape: .arrow(from: CGPoint(x: 606, y: 88), to: CGPoint(x: 624, y: 134), style: ArrowStyle()), color: blue, lineWidth: 4),
        ]
    }

    // MARK: 画面を描く

    /// 2 倍（Retina）の画像にする
    func image() -> CGImage? {
        let width = Int(Self.size.width * Self.scale)
        let height = Int(Self.size.height * Self.scale)
        guard let ctx = CGContext.makeRGBA(width: width, height: height) else { return nil }
        // 左上を原点にして、ポイントで描く
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: Self.scale, y: -Self.scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private func draw() {
        let size = Self.size
        fill(CGRect(origin: .zero, size: size), .white)

        // タイトルバー
        fill(CGRect(x: 0, y: 0, width: size.width, height: 40), gray(0.95))
        fill(CGRect(x: 0, y: 40, width: size.width, height: 1), gray(0.86))
        for (index, color) in [hex(0xFF5F57), hex(0xFEBC2E), hex(0x28C840)].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: CGRect(x: 14 + CGFloat(index) * 20, y: 14, width: 12, height: 12)).fill()
        }
        text("設定", at: CGPoint(x: size.width / 2, y: 12), font: .systemFont(ofSize: 13, weight: .semibold), color: gray(0.25), centered: true)

        // 左の一覧
        fill(CGRect(x: 0, y: 41, width: 180, height: size.height - 41), gray(0.97))
        fill(CGRect(x: 180, y: 41, width: 1, height: size.height - 41), gray(0.88))
        for (index, item) in ["一般", "プロフィール", "通知", "プライバシー", "詳細"].enumerated() {
            let y = 60 + CGFloat(index) * 34
            let selected = index == 1
            if selected {
                roundedRect(CGRect(x: 10, y: y - 7, width: 160, height: 30), radius: 7, fill: hex(0xE1EAFF))
            }
            let color = selected ? hex(0x0A64D8) : gray(0.3)
            color.setFill()
            NSBezierPath(roundedRect: CGRect(x: 22, y: y + 2, width: 12, height: 12), xRadius: 3, yRadius: 3).fill()
            text(item, at: CGPoint(x: 44, y: y), font: .systemFont(ofSize: 13, weight: selected ? .semibold : .regular), color: color)
        }

        // 見出し
        text("プロフィール", at: CGPoint(x: 212, y: 58), font: .systemFont(ofSize: 22, weight: .bold), color: gray(0.1))
        text("ほかのメンバーに表示される情報です。", at: CGPoint(x: 212, y: 92), font: Self.noteFont, color: gray(0.5))

        // 入力欄
        field(label: "名前", value: "山田 花子", in: Self.nameField)
        field(label: "メールアドレス", value: "hanako@example.com", in: Self.emailField)
        field(label: "自己紹介", value: "週末はカメラを持って、近所を散歩しています。", in: Self.bioField)
        text(Self.note, at: Self.noteOrigin, font: Self.noteFont, color: gray(0.45))

        // 写真
        let center = Self.avatarCenter
        hex(0x8FB1F7).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84)).fill()
        text("花", at: CGPoint(x: center.x, y: center.y - 17), font: .systemFont(ofSize: 30, weight: .semibold), color: .white, centered: true)
        text("写真を変更", at: CGPoint(x: center.x, y: center.y + 50), font: Self.noteFont, color: hex(0x0A64D8), centered: true)

        // ボタン
        roundedRect(Self.cancelButton, radius: 7, fill: gray(0.92))
        text("キャンセル", at: CGPoint(x: Self.cancelButton.midX, y: Self.cancelButton.minY + 8), font: .systemFont(ofSize: 14), color: gray(0.2), centered: true)
        roundedRect(Self.saveButton, radius: 7, fill: hex(0x0A84FF))
        text("保存する", at: CGPoint(x: Self.saveButton.midX, y: Self.saveButton.minY + 8), font: .systemFont(ofSize: 14, weight: .semibold), color: .white, centered: true)
    }

    private func field(label: String, value: String, in rect: CGRect) {
        text(label, at: CGPoint(x: rect.minX, y: rect.minY - 22), font: .systemFont(ofSize: 12, weight: .semibold), color: gray(0.3))
        roundedRect(rect, radius: 6, fill: .white, stroke: gray(0.8))
        text(value, at: CGPoint(x: rect.minX + 12, y: rect.minY + (rect.height - 18) / 2), font: Self.bodyFont, color: gray(0.12))
    }

    // MARK: 描く道具

    private func fill(_ rect: CGRect, _ color: NSColor) {
        color.setFill()
        rect.fill()
    }

    private func roundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        if let stroke {
            stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func text(_ string: String, at point: CGPoint, font: NSFont, color: NSColor, centered: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = centered ? (string as NSString).size(withAttributes: attributes).width : 0
        (string as NSString).draw(at: CGPoint(x: point.x - width / 2, y: point.y), withAttributes: attributes)
    }

    private func gray(_ white: CGFloat) -> NSColor { NSColor(srgbRed: white, green: white, blue: white, alpha: 1) }

    private func hex(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
