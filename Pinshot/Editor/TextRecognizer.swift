import AppKit
import Vision

/// 読み取った結果
struct TextRecognitionResult: Equatable {
    /// 読み取った文字（行ごとに改行でつなぐ）。文字がなければ空
    var text: String
    /// 読み取った文字のかたまりの位置（0〜1。Vision と同じく左下が原点）
    var boxes: [CGRect]

    static let empty = TextRecognitionResult(text: "", boxes: [])
}

/// 画像の文字を読み取る（macOS の Vision。ネットにつながず、Mac の中で読む。日本語と英語）
enum TextRecognizer {
    /// 読み取る（読み取った文字と、かたまりの位置）。読めなければ空
    static func recognize(_ image: CGImage) async -> TextRecognitionResult {
        await inBackground(fallback: .empty) { try recognizeNow(image) }
    }

    /// 読み取った結果を知らせる文（「✓ 文字をコピーしました（12 文字）」など）
    static func resultMessage(copiedCount: Int) -> String {
        copiedCount > 0 ? "✓ 文字をコピーしました（\(copiedCount) 文字）" : "文字が見つかりませんでした"
    }

    /// 読み取る（その場で。Vision が使えないときはエラー）
    static func recognizeText(_ image: CGImage) throws -> String {
        try recognizeNow(image).text
    }

    /// 読み取りは重いので、画面を止めないよう裏で行う。読めなければ記録を残して fallback を返す
    private static func inBackground<T>(fallback: T, _ work: @escaping () throws -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    NSLog("Pinshot: 文字を読み取れませんでした: \(error.localizedDescription)")
                    continuation.resume(returning: fallback)
                }
            }
        }
    }

    private static func observations(in image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ja-JP", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results ?? []
    }

    private static func recognizeNow(_ image: CGImage) throws -> TextRecognitionResult {
        let pieces = try observations(in: image).compactMap { observation -> RecognizedText? in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return RecognizedText(text: text, box: observation.boundingBox)
        }
        return TextRecognitionResult(text: RecognizedTextLayout.join(pieces), boxes: pieces.map(\.box))
    }
}

/// 読み取った文字のかたまり 1 つ
struct RecognizedText: Equatable {
    var text: String
    /// 画像の中の位置（0〜1。Vision と同じく左下が原点）
    var box: CGRect
}

/// 読み取った文字のかたまりを、読む順（上の行から、行の中は左から）につなぐ（テストで確かめる）
enum RecognizedTextLayout {
    static func join(_ pieces: [RecognizedText]) -> String {
        lines(pieces)
            .map { line in
                line.dropFirst().reduce(line.first?.text ?? "") { text, piece in
                    text + (needsSpace(between: text, and: piece.text) ? " " : "") + piece.text
                }
            }
            .joined(separator: "\n")
    }

    /// 同じ高さにあるかたまりを 1 行にまとめる（上の行から。行の中は左から）
    static func lines(_ pieces: [RecognizedText]) -> [[RecognizedText]] {
        var lines: [[RecognizedText]] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = lines.last?.last, sameLine(last.box, piece.box) {
                lines[lines.count - 1].append(piece)
            } else {
                lines.append([piece])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// 縦の真ん中の差が、低いほうの高さの半分より小さければ同じ行
    private static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.midY - b.midY) < min(a.height, b.height) / 2
    }

    /// Vision の位置（0〜1・左下が原点）を、読んだ範囲 target（画像のポイント座標・左上が原点）の中の位置にする
    static func imageRect(for box: CGRect, in target: CGRect) -> CGRect {
        CGRect(
            x: target.minX + box.minX * target.width,
            y: target.minY + (1 - box.maxY) * target.height,
            width: box.width * target.width,
            height: box.height * target.height
        )
    }

    /// 英数字どうしがくっつくときだけ、間に空白を入れる（日本語は空白を入れずにつなぐ）
    static func needsSpace(between left: String, and right: String) -> Bool {
        guard let last = left.unicodeScalars.last, let first = right.unicodeScalars.first else { return false }
        let ascii = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(127)))
        return ascii.contains(last) && ascii.contains(first)
    }
}
