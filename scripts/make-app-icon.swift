// アプリのアイコンを描いて、Assets.xcassets の AppIcon に PNG を書き出す。
// 使い方: swift scripts/make-app-icon.swift（プロジェクトのフォルダで）
//
// デザイン: メニューバーのアイコン（四隅の枠＝ファインダー）を白で描き、その中に
// 「撮って浮かせた画像」のカードと、留めるピンを置く。背景は青のグラデーションの角丸の四角。
import AppKit

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Pinshot/Assets.xcassets/AppIcon.appiconset")

// MARK: - 色

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: - 描く（1024 × 1024 の座標で描き、サイズに合わせて縮める。原点は左下）

func drawIcon(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // macOS のアイコンの決まり: 1024 の中に 824 の角丸の四角（まわりは影のための余白）
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 本体の影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x2F6BF0))
    ctx.fillPath()
    ctx.restoreGState()

    // 背景のグラデーション（上が明るい青、下が濃い青）
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [rgb(0x5AA2FF), rgb(0x2A5BDB)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
    // 上半分に、ほんのり光
    let shine = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.midY), options: [])
    ctx.restoreGState()

    // ファインダーの四隅の枠（メニューバーのアイコンと同じモチーフ）
    let frame = body.insetBy(dx: 132, dy: 132)
    let arm: CGFloat = 132
    let radius: CGFloat = 54
    ctx.saveGState()
    ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),  // 左上
        (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1), // 右上
        (CGPoint(x: frame.minX, y: frame.minY), 1, 1),   // 左下
        (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),  // 右下
    ]
    for (corner, sx, sy) in corners {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: corner.x, y: corner.y + sy * arm))
        path.addArc(
            tangent1End: corner,
            tangent2End: CGPoint(x: corner.x + sx * arm, y: corner.y),
            radius: radius
        )
        path.addLine(to: CGPoint(x: corner.x + sx * arm, y: corner.y))
        ctx.addPath(path)
    }
    ctx.strokePath()
    ctx.restoreGState()

    // 浮かせた画像のカード（少し傾けて、影を付けて浮いて見せる）
    let card = CGRect(x: -178, y: -134, width: 356, height: 268)
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 500)
    ctx.rotate(by: -6 * .pi / 180)

    let cardPath = CGPath(roundedRect: card, cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: rgb(0x0A1F5C, 0.45))
    ctx.addPath(cardPath)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // カードの中の写真（空・太陽・山）
    let photo = card.insetBy(dx: 22, dy: 22)
    let photoPath = CGPath(roundedRect: photo, cornerWidth: 14, cornerHeight: 14, transform: nil)
    ctx.saveGState()
    ctx.addPath(photoPath)
    ctx.clip()
    let sky = CGGradient(colorsSpace: space, colors: [rgb(0x8FD3FF), rgb(0xD9F1FF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: photo.maxY), end: CGPoint(x: 0, y: photo.minY), options: [])
    // 太陽
    ctx.setFillColor(rgb(0xFFC93C))
    ctx.fillEllipse(in: CGRect(x: photo.maxX - 104, y: photo.maxY - 98, width: 62, height: 62))
    // 奥の山
    let far = CGMutablePath()
    far.move(to: CGPoint(x: photo.minX, y: photo.minY))
    far.addLine(to: CGPoint(x: photo.minX, y: photo.minY + 70))
    far.addLine(to: CGPoint(x: photo.minX + 120, y: photo.minY + 150))
    far.addLine(to: CGPoint(x: photo.minX + 230, y: photo.minY + 60))
    far.addLine(to: CGPoint(x: photo.maxX, y: photo.minY + 110))
    far.addLine(to: CGPoint(x: photo.maxX, y: photo.minY))
    far.closeSubpath()
    ctx.addPath(far)
    ctx.setFillColor(rgb(0x4CC38A))
    ctx.fillPath()
    // 手前の山
    let near = CGMutablePath()
    near.move(to: CGPoint(x: photo.minX, y: photo.minY))
    near.addLine(to: CGPoint(x: photo.minX, y: photo.minY + 30))
    near.addLine(to: CGPoint(x: photo.minX + 180, y: photo.minY + 112))
    near.addLine(to: CGPoint(x: photo.maxX, y: photo.minY + 20))
    near.addLine(to: CGPoint(x: photo.maxX, y: photo.minY))
    near.closeSubpath()
    ctx.addPath(near)
    ctx.setFillColor(rgb(0x2E9E6B))
    ctx.fillPath()
    ctx.restoreGState()

    // カードを留めるピン（上の真ん中）
    let pinCenter = CGPoint(x: 0, y: card.maxY - 6)
    // 針の影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 4, height: -8), blur: 10, color: rgb(0x000000, 0.35))
    ctx.setFillColor(rgb(0xE5484D))
    ctx.fillEllipse(in: CGRect(x: pinCenter.x - 40, y: pinCenter.y - 40, width: 80, height: 80))
    ctx.restoreGState()
    // 頭の立体感
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: pinCenter.x - 40, y: pinCenter.y - 40, width: 80, height: 80))
    ctx.clip()
    let pinShade = CGGradient(colorsSpace: space, colors: [rgb(0xFF7A7E), rgb(0xC9282E)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(
        pinShade,
        startCenter: CGPoint(x: pinCenter.x - 14, y: pinCenter.y + 16), startRadius: 4,
        endCenter: pinCenter, endRadius: 46,
        options: [.drawsAfterEndLocation]
    )
    ctx.restoreGState()
    // 光の点
    ctx.setFillColor(rgb(0xFFFFFF, 0.75))
    ctx.fillEllipse(in: CGRect(x: pinCenter.x - 22, y: pinCenter.y + 6, width: 18, height: 14))

    ctx.restoreGState()
}

// MARK: - 書き出す

func png(size: Int) -> Data? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(in: ctx)
    guard let image = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

// macOS が求める大きさ（ポイント × 倍率）
let entries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    guard let data = png(size: pixels) else { fatalError("描けませんでした: \(name)") }
    try data.write(to: outputDir.appendingPathComponent(name))
    images.append([
        "idiom": "mac",
        "size": "\(entry.points)x\(entry.points)",
        "scale": "\(entry.scale)x",
        "filename": name,
    ])
}

let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDir.appendingPathComponent("Contents.json"))

// アセットカタログ自体の Contents.json
let catalog = outputDir.deletingLastPathComponent()
let catalogContents = try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted, .sortedKeys])
try catalogContents.write(to: catalog.appendingPathComponent("Contents.json"))

print("書き出しました: \(outputDir.path)")
