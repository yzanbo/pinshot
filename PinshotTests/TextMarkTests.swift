import XCTest

/// 文字マーカー（文字の位置に合わせて引く）の決まり
final class TextMarkLayoutTests: XCTestCase {
    /// 1 文字 10pt 幅の行を作る（y は行の上、高さ 20）
    private func line(x: CGFloat = 0, y: CGFloat, count: Int) -> TextLineBoxes {
        let characters = (0..<count).map { CGRect(x: x + CGFloat($0) * 10, y: y, width: 10, height: 20) }
        return TextLineBoxes(box: CGRect(x: x, y: y, width: CGFloat(count) * 10, height: 20), characters: characters)
    }

    func testSameLineSnapsToCharacters() {
        let lines = [line(y: 0, count: 10)]
        // 12〜47 をドラッグ → 真ん中（5・15・25…）を過ぎた文字の間で区切る。2 文字目（10〜）から 5 文字目（〜50）まで
        let rects = TextMarkLayout.rects(from: CGPoint(x: 12, y: 8), to: CGPoint(x: 47, y: 12), lines: lines, fallbackHeight: 18)
        XCTAssertEqual(rects, [CGRect(x: 10, y: 0, width: 40, height: 20)])
    }

    func testBackwardDragGivesSameResult() {
        let lines = [line(y: 0, count: 10)]
        let forward = TextMarkLayout.rects(from: CGPoint(x: 12, y: 8), to: CGPoint(x: 47, y: 8), lines: lines, fallbackHeight: 18)
        let backward = TextMarkLayout.rects(from: CGPoint(x: 47, y: 8), to: CGPoint(x: 12, y: 8), lines: lines, fallbackHeight: 18)
        XCTAssertEqual(forward, backward)
    }

    func testMultipleLinesLikeTextSelection() {
        let lines = [line(y: 0, count: 10), line(y: 30, count: 8), line(y: 60, count: 10)]
        let rects = TextMarkLayout.rects(from: CGPoint(x: 52, y: 10), to: CGPoint(x: 23, y: 70), lines: lines, fallbackHeight: 18)
        XCTAssertEqual(rects, [
            CGRect(x: 50, y: 0, width: 50, height: 20), // 1 行目は始めた文字から行の終わりまで
            CGRect(x: 0, y: 30, width: 80, height: 20), // 間の行はまるごと
            CGRect(x: 0, y: 60, width: 20, height: 20), // 最後の行は行の始めから終えた文字まで
        ])
    }

    func testOtherColumnIsNotIncluded() {
        // 右の段（x 300〜）の行は、左の段の行をまたいで引いても含めない
        let lines = [line(y: 0, count: 10), line(x: 300, y: 30, count: 5), line(y: 60, count: 10)]
        let rects = TextMarkLayout.rects(from: CGPoint(x: 2, y: 10), to: CGPoint(x: 98, y: 70), lines: lines, fallbackHeight: 18)
        XCTAssertEqual(rects.count, 2)
        XCTAssertFalse(rects.contains { $0.minX >= 300 })
    }

    func testFallsBackToStraightBandWithoutText() {
        let rects = TextMarkLayout.rects(from: CGPoint(x: 10, y: 100), to: CGPoint(x: 60, y: 130), lines: [], fallbackHeight: 18)
        XCTAssertEqual(rects, [CGRect(x: 10, y: 91, width: 50, height: 18)])
    }

    func testClickWithoutMovingGivesNothing() {
        let rects = TextMarkLayout.rects(from: CGPoint(x: 12, y: 8), to: CGPoint(x: 13, y: 8), lines: [line(y: 0, count: 10)], fallbackHeight: 18)
        XCTAssertTrue(rects.isEmpty)
    }

    func testDegenerateCharacterBoxesAreSplitEvenly() {
        // Vision が 1 文字ずつの位置を返さない（どれも行と同じ）ときは等分する
        let lineBox = CGRect(x: 0.1, y: 0.5, width: 0.4, height: 0.1)
        let recognized = [RecognizedLine(box: lineBox, characters: Array(repeating: lineBox, count: 4))]
        let lines = TextMarkLayout.lines(from: recognized, imageSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(lines.first?.characters.map(\.minX), [10, 20, 30, 40])
        XCTAssertEqual(lines.first?.box, CGRect(x: 10, y: 40, width: 40, height: 10))
    }

    func testAnnotationMovesAndHits() {
        let mark = Annotation(shape: .textMark([CGRect(x: 0, y: 0, width: 50, height: 20)], style: TextMarkStyle(kind: .underline)), color: .red, lineWidth: 2)
        XCTAssertTrue(mark.isMeaningful)
        XCTAssertEqual(mark.tool, .textMark)
        XCTAssertTrue(mark.hitTest(CGPoint(x: 25, y: 10), tolerance: 2))
        let moved = mark.translated(by: CGVector(dx: 10, dy: 5))
        XCTAssertEqual(moved.shape, .textMark([CGRect(x: 10, y: 5, width: 50, height: 20)], style: TextMarkStyle(kind: .underline)))
    }

    func testAnnotationRoundTripsThroughJSON() throws {
        let mark = Annotation(shape: .textMark([CGRect(x: 1, y: 2, width: 3, height: 4)], style: TextMarkStyle(kind: .box)), color: .red, lineWidth: 2)
        let decoded = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(mark))
        XCTAssertEqual(decoded, mark)
    }
}

/// 文字の線がある高さに合わせる（Vision の行の範囲は、日本語では下に余白があり、下にずれるため）
final class TextInkTests: XCTestCase {
    func testVerticalRangeFindsInkRows() {
        // 背景 250 の 40×20 に、5〜12 行目だけ暗い線
        let width = 40, height = 20
        var pixels = [UInt8](repeating: 250, count: width * height)
        for y in 5...12 { for x in 4..<36 { pixels[y * width + x] = 20 } }
        XCTAssertEqual(TextInk.verticalRange(luminance: pixels, width: width, height: height), 5...12)
    }

    func testVerticalRangeWorksOnDarkBackgroundAndIgnoresSpecks() {
        // 暗い背景に明るい文字。1 画素だけの汚れは文字とみなさない
        let width = 40, height = 20
        var pixels = [UInt8](repeating: 30, count: width * height)
        pixels[1 * width + 3] = 255
        for y in 8...14 { for x in 0..<20 { pixels[y * width + x] = 240 } }
        XCTAssertEqual(TextInk.verticalRange(luminance: pixels, width: width, height: height), 8...14)
        XCTAssertNil(TextInk.verticalRange(luminance: [UInt8](repeating: 128, count: 100), width: 10, height: 10))
    }

    func testFittedMovesBoxToInk() {
        // 文字の線は 20〜34 行目。Vision の範囲は 18〜44（下に余白がある）とする
        let image = TestImages.make(width: 100, height: 60) { x, y in
            (20...34).contains(y) && (10..<90).contains(x) ? 0 : 255
        }
        let box = CGRect(x: 5, y: 18, width: 90, height: 26)
        let line = TextLineBoxes(box: box, characters: [CGRect(x: 5, y: 18, width: 45, height: 26), CGRect(x: 50, y: 18, width: 45, height: 26)])
        let fitted = TextInk.fitted([line], image: image, imageSize: CGSize(width: 100, height: 60))
        XCTAssertEqual(fitted.first?.box, CGRect(x: 5, y: 20, width: 90, height: 15))
        XCTAssertEqual(fitted.first?.characters.map(\.minY), [20, 20])
        XCTAssertEqual(fitted.first?.characters.map(\.minX), [5, 50], "横の位置は変えない")
    }

    func testFittedKeepsLineWithoutInk() {
        let image = TestImages.make(width: 50, height: 50) { _, _ in 255 }
        let line = TextLineBoxes(box: CGRect(x: 5, y: 10, width: 40, height: 20), characters: [CGRect(x: 5, y: 10, width: 40, height: 20)])
        XCTAssertEqual(TextInk.fitted([line], image: image, imageSize: CGSize(width: 50, height: 50)), [line])
    }
}
