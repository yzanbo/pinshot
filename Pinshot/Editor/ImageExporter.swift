import AppKit
import UniformTypeIdentifiers

/// 書き込みを合成した画像を作り、コピー・保存する
enum ImageExporter {
    /// 元の画像の解像度（実ピクセル）のまま、書き込みを合成する
    static func render(
        base: CGImage,
        imageSize: CGSize,
        annotations: [Annotation],
        effects: EffectImages,
        shadow: Bool = true,
        crop: CGRect? = nil
    ) -> CGImage? {
        guard let full = renderFull(base: base, imageSize: imageSize, annotations: annotations, effects: effects, shadow: shadow) else {
            return nil
        }
        // トリミングしているときは、その範囲（画像のポイント座標）だけを切り出す
        guard let crop, crop != CGRect(origin: .zero, size: imageSize) else { return full }
        let scaleX = CGFloat(base.width) / imageSize.width
        let scaleY = CGFloat(base.height) / imageSize.height
        let pixelRect = CGRect(
            x: crop.minX * scaleX,
            y: crop.minY * scaleY,
            width: crop.width * scaleX,
            height: crop.height * scaleY
        ).integral
        return full.cropping(to: pixelRect)
    }

    private static func renderFull(
        base: CGImage,
        imageSize: CGSize,
        annotations: [Annotation],
        effects: EffectImages,
        shadow: Bool
    ) -> CGImage? {
        let width = base.width
        let height = base.height
        guard let ctx = CGContext.makeRGBA(width: width, height: height, space: base.rgbColorSpace) else { return nil }

        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard !annotations.isEmpty else { return ctx.makeImage() }

        // 左上を原点にして、画像のポイント座標で描けるようにする
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: CGFloat(width) / imageSize.width, y: CGFloat(height) / imageSize.height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        AnnotationRenderer.draw(annotations, in: ctx, imageSize: imageSize, effects: effects, shadow: shadow)
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }

    /// 余白・背景・角丸・影を付けた画像にする。戻り値の pointSize は背景を含めた大きさ
    static func decorate(
        _ image: CGImage,
        pointSize: CGSize,
        with decoration: ExportDecoration
    ) -> (image: CGImage, pointSize: CGSize)? {
        let scale = CGFloat(image.width) / max(pointSize.width, 1)
        let padding = decoration.padding.points * scale
        let width = Int((CGFloat(image.width) + padding * 2).rounded())
        let height = Int((CGFloat(image.height) + padding * 2).rounded())
        guard let ctx = CGContext.makeRGBA(width: width, height: height) else { return nil }

        // 背景（単色か、左上から右下へのグラデーション）
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let colors = decoration.background.colors
        if colors.count >= 2,
           let gradient = CGGradient(colorsSpace: ctx.colorSpace, colors: colors.map(\.cgColor) as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: full.maxY), end: CGPoint(x: full.maxX, y: 0), options: [])
        } else if let color = colors.first {
            ctx.setFillColor(color.cgColor)
            ctx.fill(full)
        }

        let imageRect = CGRect(x: padding, y: padding, width: CGFloat(image.width), height: CGFloat(image.height))
        let radius = min(decoration.corner.points * scale, min(imageRect.width, imageRect.height) / 2)
        let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // 影（画像の形の板を描いて、その影を落とす）
        if decoration.shadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 28 * scale, color: NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 角を丸めた画像
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(image, in: imageRect)
        ctx.restoreGState()

        guard let result = ctx.makeImage() else { return nil }
        let padPoints = decoration.padding.points
        return (result, CGSize(width: pointSize.width + padPoints * 2, height: pointSize.height + padPoints * 2))
    }

    static func pngData(_ image: CGImage, pointSize: CGSize) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        // ポイントの大きさを入れておくと、Retina で撮った画像がプレビューで等倍に見える
        rep.size = pointSize
        return rep.representation(using: .png, properties: [:])
    }

    static func writeToPasteboard(_ image: CGImage, pointSize: CGSize) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = pngData(image, pointSize: pointSize) {
            pasteboard.setData(png, forType: .png)
        }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = pointSize
        if let tiff = rep.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Pinshot \(formatter.string(from: Date())).png"
    }
}
