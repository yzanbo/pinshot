import XCTest

/// スクロールしながら撮った画像のつなぎ合わせ
final class ScrollStitcherTests: XCTestCase {
    private let width = 300
    private let viewport = 400

    /// ページを step ピクセルずつスクロールしながら撮った画像（count 枚）
    private func frames(of page: CGImage, step: Int, count: Int) -> [CGImage] {
        (0..<count).map { TestImages.rows(($0 * step)..<($0 * step + viewport), of: page) }
    }

    private func signature(_ image: CGImage) -> FrameSignature {
        FrameSignature(image: image)!
    }

    func testFindsScrollOffset() {
        let page = TestImages.page(width: width, height: 1200)
        let shots = frames(of: page, step: 150, count: 2)
        let result = ScrollStitcher.findOffset(previous: signature(shots[0]), next: signature(shots[1]))
        XCTAssertEqual(result, .moved(.init(offset: 150, header: 0, footer: 0)))
    }

    func testSameFrameIsUnchanged() {
        let page = TestImages.page(width: width, height: 600)
        let shot = TestImages.rows(0..<viewport, of: page)
        XCTAssertEqual(ScrollStitcher.findOffset(previous: signature(shot), next: signature(shot)), .unchanged)
    }

    func testMostlyStaticFrameIsUnchanged() {
        // 一部だけが動いている（動画・スピナーなど）ときは、スクロールしていないとみなす
        let page = TestImages.page(width: width, height: 600)
        let still = TestImages.rows(0..<viewport, of: page)
        let animated = TestImages.make(width: width, height: viewport) { x, y in
            if (180..<200).contains(y) { return UInt8((x * 5 + y) % 256) }
            let v = TestImages.pixels(of: TestImages.rows(y..<(y + 1), of: still))
            return v[x * 4]
        }
        XCTAssertEqual(ScrollStitcher.findOffset(previous: signature(still), next: signature(animated)), .unchanged)
    }

    func testUnrelatedFramesAreLost() {
        let a = TestImages.rows(0..<viewport, of: TestImages.page(width: width, height: viewport))
        let b = TestImages.make(width: width, height: viewport) { x, y in UInt8((x * 13 + y * 31 + x * y) % 256) }
        XCTAssertEqual(ScrollStitcher.findOffset(previous: signature(a), next: signature(b)), .lost)
    }

    func testStitchedImageMatchesThePage() {
        let page = TestImages.page(width: width, height: 1400)
        let shots = frames(of: page, step: 150, count: 5)
        let stitch = ScrollStitch(first: shots[0])
        for (previous, next) in zip(shots, shots.dropFirst()) {
            guard case .moved(let match) = ScrollStitcher.findOffset(
                previous: signature(previous), next: signature(next), header: stitch.header, footer: stitch.footer
            ) else { return XCTFail("つなげませんでした") }
            stitch.append(next, match: match)
        }
        let expectedHeight = viewport + 150 * 4
        XCTAssertEqual(stitch.totalHeight, expectedHeight)
        let composed = stitch.compose()!
        XCTAssertEqual(composed.height, expectedHeight)
        XCTAssertEqual(TestImages.pixels(of: composed), TestImages.pixels(of: TestImages.rows(0..<expectedHeight, of: page)))

        // 操作パネルに出す縮小画像は、決めた幅に縮める
        XCTAssertEqual(stitch.preview()?.width, 160)
    }

    func testFixedHeaderAndFooterAppearOnce() {
        // 上 40 行（ヘッダー）と下 30 行（フッター）は動かず、その間だけがスクロールする
        let header = 40, footer = 30, step = 100
        let content = TestImages.page(width: width, height: 1200)
        func shot(_ index: Int) -> CGImage {
            TestImages.make(width: width, height: viewport) { x, y in
                if y < header { return 30 }
                if y >= viewport - footer { return 220 }
                let v = TestImages.pixels(of: TestImages.rows((index * step + y)..<(index * step + y + 1), of: content))
                return v[x * 4]
            }
        }
        let shots = (0..<3).map(shot)
        let stitch = ScrollStitch(first: shots[0])
        for (previous, next) in zip(shots, shots.dropFirst()) {
            guard case .moved(let match) = ScrollStitcher.findOffset(
                previous: signature(previous), next: signature(next), header: stitch.header, footer: stitch.footer
            ) else { return XCTFail("つなげませんでした") }
            XCTAssertEqual(match.offset, step)
            stitch.append(next, match: match)
        }
        XCTAssertEqual(stitch.header, header)
        XCTAssertEqual(stitch.footer, footer)
        // ヘッダー + 中身（1 枚目の中身 + 2 回ぶん）+ フッター
        XCTAssertEqual(stitch.compose()?.height, viewport + step * 2)
    }

    func testCopyRowsKeepsOnlyTheRows() {
        let page = TestImages.page(width: width, height: 200)
        let strip = ScrollStitch.copyRows(50..<80, of: page)!
        XCTAssertEqual(strip.height, 30)
        XCTAssertEqual(TestImages.pixels(of: strip), TestImages.pixels(of: TestImages.rows(50..<80, of: page)))
        // 範囲の外は切り捨てる
        XCTAssertEqual(ScrollStitch.copyRows(190..<260, of: page)?.height, 10)
        XCTAssertNil(ScrollStitch.copyRows(300..<320, of: page))
    }
}
