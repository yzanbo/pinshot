import CoreGraphics

/// 画像の中の文字の 1 行（読み取った文字の位置。画像のポイント座標・左上が原点）
struct TextLineBoxes: Equatable {
    /// 行の範囲
    var box: CGRect
    /// 1 文字ずつの範囲（左から）。横の位置だけを使う
    var characters: [CGRect]
}

/// 文字マーカーを、ドラッグした所の文字に合わせて引く決まり（テストで確かめる）。
/// 文章を選ぶときと同じく、始めた文字から終えた文字までを、行ごとの四角にする
enum TextMarkLayout {
    /// start から end までドラッグしたときの、行ごとの四角。
    /// 始めた所に文字がなければ、ドラッグした所にまっすぐ（高さ fallbackHeight の帯で）引く
    static func rects(from start: CGPoint, to end: CGPoint, lines: [TextLineBoxes], fallbackHeight: CGFloat) -> [CGRect] {
        let sorted = lines.filter { !$0.characters.isEmpty }.sorted { $0.box.midY < $1.box.midY }
        guard let begin = locate(start, in: sorted, strict: true), let finish = locate(end, in: sorted, strict: false) else {
            return [straightBand(from: start, to: end, height: fallbackHeight)]
        }
        // 上の行を始まりにする（同じ行なら左を始まりに）
        let (first, last) = (begin.line, begin.caret) <= (finish.line, finish.caret) ? (begin, finish) : (finish, begin)
        if first.line == last.line {
            return rect(in: sorted[first.line], from: first.caret, to: last.caret).map { [$0] } ?? []
        }
        let firstLine = sorted[first.line]
        let lastLine = sorted[last.line]
        // 間の行は、始めた行と終えた行の横の範囲に重なるものだけ（となりの段の文字は含めない）
        let columnMinX = min(firstLine.box.minX, lastLine.box.minX)
        let columnMaxX = max(firstLine.box.maxX, lastLine.box.maxX)
        var result: [CGRect] = []
        if let head = rect(in: firstLine, from: first.caret, to: firstLine.characters.count) { result.append(head) }
        for index in (first.line + 1)..<last.line {
            let line = sorted[index]
            guard line.box.maxX > columnMinX, line.box.minX < columnMaxX,
                  let whole = rect(in: line, from: 0, to: line.characters.count) else { continue }
            result.append(whole)
        }
        if let tail = rect(in: lastLine, from: 0, to: last.caret) { result.append(tail) }
        return result
    }

    /// point のある行と、文字の間の位置（0 なら最初の文字の前）。
    /// strict なら行の近くでなければ nil、そうでなければいちばん近い行にする
    static func locate(_ point: CGPoint, in lines: [TextLineBoxes], strict: Bool) -> (line: Int, caret: Int)? {
        let candidates = lines.indices.filter { index in
            guard strict else { return true }
            let box = lines[index].box
            let reachY = box.height * 0.5
            let reachX = box.height * 1.5
            return point.y >= box.minY - reachY && point.y <= box.maxY + reachY
                && point.x >= box.minX - reachX && point.x <= box.maxX + reachX
        }
        // 縦の近さを先に、同じくらいなら横の近さで選ぶ
        guard let index = candidates.min(by: { distance(point, to: lines[$0].box) < distance(point, to: lines[$1].box) }) else { return nil }
        let caret = lines[index].characters.filter { $0.midX < point.x }.count
        return (index, caret)
    }

    /// 行の from 文字目から to 文字目の手前までの四角（高さは行に合わせる）。文字がなければ nil
    static func rect(in line: TextLineBoxes, from: Int, to: Int) -> CGRect? {
        let lower = max(0, min(from, to))
        let upper = min(line.characters.count, max(from, to))
        guard lower < upper else { return nil }
        let chars = line.characters[lower..<upper]
        let minX = chars.map(\.minX).min() ?? line.box.minX
        let maxX = chars.map(\.maxX).max() ?? line.box.maxX
        return CGRect(x: minX, y: line.box.minY, width: maxX - minX, height: line.box.height)
    }

    /// 文字がない所で引くときの、まっすぐな帯（始めた高さで、横に引く）
    private static func straightBand(from start: CGPoint, to end: CGPoint, height: CGFloat) -> CGRect {
        CGRect(x: min(start.x, end.x), y: start.y - height / 2, width: abs(end.x - start.x), height: height)
    }

    /// 縦の離れ方を重く見た距離（行を選ぶため）
    private static func distance(_ point: CGPoint, to box: CGRect) -> CGFloat {
        let dy = point.y < box.minY ? box.minY - point.y : (point.y > box.maxY ? point.y - box.maxY : 0)
        let dx = point.x < box.minX ? box.minX - point.x : (point.x > box.maxX ? point.x - box.maxX : 0)
        return dy * 4 + dx + abs(point.y - box.midY) * 0.01
    }

    // MARK: - 読み取った文字から行を作る

    /// Vision の行（0〜1・左下が原点）を、画像のポイント座標の行にする。
    /// 1 文字ずつの位置が分からない（どれも行と同じ幅になる）ときは、行を文字の数で等分する
    static func lines(from recognized: [RecognizedLine], imageSize: CGSize) -> [TextLineBoxes] {
        let target = CGRect(origin: .zero, size: imageSize)
        return recognized.compactMap { line in
            let box = RecognizedTextLayout.imageRect(for: line.box, in: target)
            guard box.width > 0, box.height > 0, !line.characters.isEmpty else { return nil }
            let characters = line.characters.map { RecognizedTextLayout.imageRect(for: $0, in: target) }
            let degenerate = characters.count > 1 && characters.filter { $0.width >= box.width * 0.9 }.count * 2 >= characters.count
            if degenerate {
                let width = box.width / CGFloat(characters.count)
                let even = characters.indices.map { CGRect(x: box.minX + CGFloat($0) * width, y: box.minY, width: width, height: box.height) }
                return TextLineBoxes(box: box, characters: even)
            }
            return TextLineBoxes(box: box, characters: characters)
        }
    }
}

/// 文字マーカーの形（描く・当たりを見る・範囲を出すのに使う）
enum TextMarkGeometry {
    /// 蛍光ペンで塗る四角（文字より少し大きく）
    static func highlightRect(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -rect.height * 0.08, dy: -rect.height * 0.1)
    }

    /// 下線の高さ（文字の下の辺から少し下）
    static func underlineY(_ rect: CGRect, lineWidth: CGFloat) -> CGFloat {
        rect.maxY + lineWidth / 2 + max(1, rect.height * 0.06)
    }

    /// 囲みの四角
    static func boxRect(_ rect: CGRect, lineWidth: CGFloat) -> CGRect {
        let pad = max(2, rect.height * 0.15) + lineWidth / 2
        return rect.insetBy(dx: -pad, dy: -pad)
    }

    /// 描いたときに占める範囲（線の太さも含む）
    static func outer(_ rect: CGRect, kind: TextMarkKind, lineWidth: CGFloat) -> CGRect {
        switch kind {
        case .highlight:
            return highlightRect(rect)
        case .underline:
            let y = underlineY(rect, lineWidth: lineWidth)
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: y + lineWidth / 2 - rect.minY)
                .insetBy(dx: -lineWidth / 2, dy: 0)
        case .strikethrough:
            return rect.insetBy(dx: -lineWidth / 2, dy: 0)
        case .box:
            return boxRect(rect, lineWidth: lineWidth).insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        }
    }
}
