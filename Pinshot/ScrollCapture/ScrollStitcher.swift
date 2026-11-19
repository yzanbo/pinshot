import CoreGraphics
import Foundation

/// 1 枚の画像の「行ごとの指紋」。前後の画像で同じ行を探して、どれだけスクロールしたかを求めるのに使う
struct FrameSignature: Equatable {
    /// 行ごとのハッシュ（上から順）
    let rows: [UInt64]
    /// ほぼ単色の行（どこにでも現れるので、位置合わせには使わない）
    let uniform: [Bool]

    var height: Int { rows.count }

    /// 横を sampleWidth ピクセルに縮め（縦はそのまま）、行ごとに明るさの並びをハッシュにする。
    /// スクロール中だけ右端に出るスクロールバーで行が食い違わないよう、左右の端は使わない
    init?(image fullImage: CGImage, sampleWidth: Int = 192) {
        let left = Int(Double(fullImage.width) * 0.02)
        let right = Int(Double(fullImage.width) * 0.06)
        let image = fullImage.cropping(to: CGRect(
            x: left, y: 0, width: max(1, fullImage.width - left - right), height: fullImage.height
        )) ?? fullImage
        let width = sampleWidth
        let height = image.height
        guard height > 0, let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        // 同じ内容なら必ず同じ結果になるよう、補間しない
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else { return nil }

        // ビットマップのメモリは、上の行から順に並んでいる
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        var rows = [UInt64](repeating: 0, count: height)
        var uniform = [Bool](repeating: false, count: height)
        for y in 0..<height {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325 // FNV-1a
            var low: UInt8 = 255
            var high: UInt8 = 0
            let row = pixels + y * width
            for x in 0..<width {
                let value = row[x]
                low = min(low, value)
                high = max(high, value)
                // 文字のにじみなどの小さな差を無視するため、明るさを 32 段階にまとめる
                hash = (hash ^ UInt64(value >> 3)) &* 0x0000_0100_0000_01b3
            }
            rows[y] = hash
            uniform[y] = high &- low < 6
        }
        self.rows = rows
        self.uniform = uniform
    }

    init(rows: [UInt64], uniform: [Bool]) {
        self.rows = rows
        self.uniform = uniform
    }
}

enum ScrollStitcher {
    struct Match: Equatable {
        /// 内容が上に動いた量（ピクセル）。下にスクロールした量
        let offset: Int
        /// 上の固定部分（ヘッダー）の高さ
        let header: Int
        /// 下の固定部分（フッター）の高さ
        let footer: Int
    }

    enum Result: Equatable {
        /// 下にスクロールした
        case moved(Match)
        /// 変わっていない（スクロールしていない、またはいちばん下まで来た）
        case unchanged
        /// 重なりが見つからない（速すぎる・上にスクロールした・内容が大きく変わった）
        case lost
    }

    /// previous から next へ、どれだけ下にスクロールしたかを求める。
    /// header・footer に値を渡すと、その固定部分を使う（最初に見つけた値を使い続ける）
    static func findOffset(
        previous: FrameSignature,
        next: FrameSignature,
        header fixedHeader: Int? = nil,
        footer fixedFooter: Int? = nil
    ) -> Result {
        let height = min(previous.height, next.height)
        guard height > 16 else { return .lost }
        if previous.rows == next.rows { return .unchanged }

        // ほとんどの行が同じ位置のままなら、スクロールしていない（動画・スピナーなど、一部だけが動いている）
        var stayed = 0
        var compared = 0
        for i in 0..<height where !next.uniform[i] {
            compared += 1
            if next.rows[i] == previous.rows[i] { stayed += 1 }
        }
        if compared >= 8, Double(stayed) / Double(compared) >= 0.9 { return .unchanged }

        // 上下の、位置も中身も同じ帯を固定部分とみなす
        var header = 0
        while header < height, previous.rows[header] == next.rows[header] { header += 1 }
        var footer = 0
        while footer < height - header, previous.rows[height - 1 - footer] == next.rows[height - 1 - footer] { footer += 1 }
        if header + footer >= height - 8 { return .unchanged }
        if let fixedHeader { header = min(fixedHeader, header) }
        if let fixedFooter { footer = min(fixedFooter, footer) }

        let top = header
        let bottom = height - footer
        let contentHeight = bottom - top
        guard contentHeight > 16 else { return .lost }

        // 前の画像の行を、ハッシュから引けるようにする（何度も出てくる行は当てにならないので使わない）
        var index: [UInt64: [Int]] = [:]
        for j in top..<bottom where !previous.uniform[j] {
            index[previous.rows[j], default: []].append(j)
        }

        // 次の画像の各行が、前の画像のどの行と同じかを調べ、ずれの量に投票する
        var votes: [Int: Int] = [:]
        let minOverlap = 8
        for i in top..<bottom where !next.uniform[i] {
            guard let candidates = index[next.rows[i]], candidates.count <= 4 else { continue }
            for j in candidates {
                let offset = j - i
                if offset > 0, offset <= contentHeight - minOverlap {
                    votes[offset, default: 0] += 1
                }
            }
        }
        guard let best = votes.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }),
              best.value >= 4 else { return .lost }

        // 重なる部分の行が本当に一致しているかを確かめる
        let offset = best.key
        var checked = 0
        var matched = 0
        for i in top..<(bottom - offset) where !next.uniform[i] {
            checked += 1
            if next.rows[i] == previous.rows[i + offset] { matched += 1 }
        }
        guard checked >= 4, Double(matched) / Double(checked) >= 0.7 else { return .lost }
        return .moved(Match(offset: offset, header: header, footer: footer))
    }
}

/// スクロールしながら撮った画像を、1 枚の縦長の画像につなぐ。
/// 撮った画像は丸ごとは持たず、新しく見えた行だけを写し取って持つ（長いページでもメモリが膨らまないように）
final class ScrollStitch {
    /// つないだ帯（上から順。それぞれ、撮った画像から必要な行だけを写し取ったもの）
    private var strips: [CGImage] = []
    private var stripsHeight = 0
    /// 操作パネルに出す縮小画像用に、帯を足すたびに縮めておいたもの
    private var previewStrips: [CGImage] = []
    private let previewScale: CGFloat

    private let first: CGImage
    private(set) var last: CGImage
    /// 最初に見つけた固定部分（以後は同じ値を使う）
    private(set) var header: Int?
    private(set) var footer: Int?

    let width: Int

    /// previewWidth: 操作パネルに出す縮小画像の幅（ピクセル）
    init(first: CGImage, previewWidth: CGFloat = 160) {
        self.first = first
        self.last = first
        self.width = first.width
        self.previewScale = min(1, previewWidth / CGFloat(max(first.width, 1)))
    }

    /// いまつながっている高さ（ピクセル、下の固定部分を含む）
    var totalHeight: Int {
        strips.isEmpty ? first.height : stripsHeight + (footer ?? 0)
    }

    /// 下にスクロールした画像を足す
    func append(_ image: CGImage, match: ScrollStitcher.Match) {
        let height = min(image.height, last.height)
        if header == nil { header = match.header }
        if footer == nil { footer = match.footer }
        let footer = self.footer ?? 0
        let bottom = height - footer

        if strips.isEmpty {
            // 1 枚目は、下の固定部分より上をすべて使う
            addStrip(from: first, rows: 0..<bottom)
        }
        // 新しく見えた部分（下の固定部分のすぐ上の offset 行）だけを足す
        let start = max(header ?? 0, bottom - match.offset)
        if start < bottom {
            addStrip(from: image, rows: start..<bottom)
        }
        last = image
    }

    /// つないだ画像を作る
    func compose() -> CGImage? {
        guard !strips.isEmpty else { return first }
        var parts = strips
        // 最後に、下の固定部分を 1 回だけ付ける
        if let footerStrip { parts.append(footerStrip) }
        return Self.stack(parts, width: width, space: first.rgbColorSpace)
    }

    /// 操作パネルに出す縮小画像
    func preview() -> CGImage? {
        var parts: [CGImage] = []
        if strips.isEmpty {
            if let small = Self.scaled(first, by: previewScale) { parts.append(small) }
        } else {
            parts = previewStrips
            if let footerStrip, let small = Self.scaled(footerStrip, by: previewScale) { parts.append(small) }
        }
        guard let widest = parts.map(\.width).max() else { return nil }
        return Self.stack(parts, width: widest, space: first.rgbColorSpace)
    }

    // MARK: - 中で使う

    /// 下の固定部分（最後に撮った画像から写し取る）
    private var footerStrip: CGImage? {
        guard let footer, footer > 0 else { return nil }
        return Self.copyRows((last.height - footer)..<last.height, of: last)
    }

    private func addStrip(from image: CGImage, rows: Range<Int>) {
        guard let strip = Self.copyRows(rows, of: image) else { return }
        strips.append(strip)
        stripsHeight += strip.height
        if let small = Self.scaled(strip, by: previewScale) {
            previewStrips.append(small)
        }
    }

    /// image の rows の行（上から数える）だけを、新しいビットマップに写し取る。
    /// cropping(to:) だけだと、切り抜いた画像が元の画像を丸ごと持ち続けるため
    static func copyRows(_ rows: Range<Int>, of image: CGImage) -> CGImage? {
        let rows = rows.clamped(to: 0..<image.height)
        guard !rows.isEmpty,
              let cropped = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count)),
              let ctx = CGContext.makeRGBA(width: image.width, height: rows.count, space: image.rgbColorSpace)
        else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: image.width, height: rows.count))
        return ctx.makeImage()
    }

    private static func scaled(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        guard scale < 1 else { return image }
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let ctx = CGContext.makeRGBA(width: width, height: height, space: image.rgbColorSpace) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// 帯を上から順に縦に並べる（CGContext は左下が原点なので、上の帯ほど y が大きい）
    private static func stack(_ parts: [CGImage], width: Int, space: CGColorSpace?) -> CGImage? {
        let total = parts.reduce(0) { $0 + $1.height }
        guard let ctx = CGContext.makeRGBA(width: max(1, width), height: max(1, total), space: space) else { return nil }
        ctx.interpolationQuality = .none
        var y = total
        for part in parts {
            y -= part.height
            ctx.draw(part, in: CGRect(x: 0, y: y, width: part.width, height: part.height))
        }
        return ctx.makeImage()
    }
}
