import CoreGraphics
import XCTest

/// テスト用の画像を作る・比べる
enum TestImages {
    /// (x, y) の明るさ（0〜255）を返す関数から、グレーの RGBA 画像を作る（y は上から数える）
    static func make(width: Int, height: Int, value: (Int, Int) -> UInt8) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = value(x, y)
                let i = (y * width + x) * 4
                bytes[i] = v
                bytes[i + 1] = v
                bytes[i + 2] = v
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    /// 行ごとに違う模様の、長いページのような画像（8 ピクセルごとに明るさを変える）
    static func page(width: Int, height: Int) -> CGImage {
        make(width: width, height: height) { x, y in
            var z = UInt64(y) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(x / 8) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 31)) &* 0x94D0_49BB_1331_11EB
            return UInt8(truncatingIfNeeded: z >> 24)
        }
    }

    /// image の上から rows 行目までを切り抜く
    static func rows(_ rows: Range<Int>, of image: CGImage) -> CGImage {
        image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count))!
    }

    /// 画像の画素（RGBA）。描き直して並びをそろえてから取り出す
    static func pixels(of image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
