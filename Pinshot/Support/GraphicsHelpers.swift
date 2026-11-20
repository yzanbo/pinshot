import CoreGraphics
import Foundation
import ImageIO

extension CGContext {
    /// 画像を作るための、RGBA（8 ビット・透明度付き）の描き先。space を省くと sRGB
    static func makeRGBA(width: Int, height: Int, space: CGColorSpace? = nil) -> CGContext? {
        guard width > 0, height > 0, let space = space ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

extension CGImage {
    /// 画像のファイル（PNG など）を読む。読めなければ nil
    /// 読んだ時点で展開しておく（後回しにすると、描くときにファイルから読み直すので、
    /// 履歴をまとめる・消すなどでファイルがなくなったあとに描くと、画像が空になる）
    static func load(contentsOf url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// size（ピクセル）に描き直した画像（履歴の縮小画像など）
    func scaled(to size: CGSize) -> CGImage? {
        guard let ctx = CGContext.makeRGBA(width: Int(size.width), height: Int(size.height), space: rgbColorSpace) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(self, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    /// RGB の画像なら、その色空間（グレーなどのときは nil。描き先を作るときに sRGB に倒す）
    var rgbColorSpace: CGColorSpace? {
        colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
    }
}
