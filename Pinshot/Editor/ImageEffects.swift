import Accelerate
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// モザイク・ぼかしに使う、画像全体を加工した画像（使うときだけ作る）
struct EffectImages {
    var pixelated: NSImage?
    var blurred: NSImage?
}

/// 画像全体を加工する（モザイク・ぼかし）
enum ImageEffects {
    /// 画像全体をモザイクにする（1 マスはおよそ 8 ポイント）
    static func pixelated(_ image: CGImage, size: CGSize) -> NSImage? {
        let input = CIImage(cgImage: image)
        let pixelsPerPoint = CGFloat(image.width) / max(size.width, 1)

        let filter = CIFilter.pixellate()
        filter.inputImage = input.clampedToExtent()
        filter.scale = Float(max(6, pixelsPerPoint * 8))
        filter.center = .zero

        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: size)
    }

    /// 画像全体をぼかす（半径はおよそ 10 ポイント）。
    /// Core Image のぼかしは環境によって画像を作れないことがあるため、Accelerate（vImage）で CPU 処理する
    static func blurred(_ image: CGImage, size: CGSize) -> NSImage? {
        let width = image.width
        let height = image.height
        guard let ctx = CGContext.makeRGBA(width: width, height: height), let pixels = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let rowBytes = ctx.bytesPerRow
        let byteCount = rowBytes * height
        var scratch = [UInt8](repeating: 0, count: byteCount)

        let pixelsPerPoint = CGFloat(width) / max(size.width, 1)
        let radius = max(2, Int(pixelsPerPoint * 10))
        let kernel = UInt32(radius * 2 + 1)
        let succeeded = scratch.withUnsafeMutableBytes { scratchBytes -> Bool in
            guard let scratchPointer = scratchBytes.baseAddress else { return false }
            var source = vImage_Buffer(data: pixels, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
            var destination = vImage_Buffer(
                data: scratchPointer, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes
            )
            // 山形のぼかしを 2 回かけると、ガウスぼかしに近い仕上がりになる
            for _ in 0..<2 {
                let error = vImageTentConvolve_ARGB8888(
                    &source, &destination, nil, 0, 0, kernel, kernel, nil, vImage_Flags(kvImageEdgeExtend)
                )
                guard error == kvImageNoError else { return false }
                pixels.copyMemory(from: scratchPointer, byteCount: byteCount)
            }
            return true
        }
        guard succeeded else { return nil }

        guard let blurred = ctx.makeImage() else { return nil }
        return NSImage(cgImage: blurred, size: size)
    }
}
