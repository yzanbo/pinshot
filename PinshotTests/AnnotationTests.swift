import XCTest

/// 書き込みのデータ（当たり判定・移動・スタイルの反映・文字の大きさ・保存形式）
final class AnnotationTests: XCTestCase {
    private func style(color: RGBAColor = .blue, width: CGFloat = 9, opacity: CGFloat = 1) -> EditorStyle {
        var arrow = ArrowStyle()
        arrow.startHead = true
        return EditorStyle(
            color: color,
            lineWidths: [.rectangle: width, .arrow: width],
            rectangle: ShapeStyle(),
            ellipse: ShapeStyle(),
            arrow: arrow,
            counterSize: .large,
            counter: CounterStyle(),
            text: TextStyle(),
            textMark: TextMarkStyle(),
            opacity: opacity
        )
    }

    private let arrow = Annotation(
        shape: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 110, y: 10), style: ArrowStyle()),
        color: .red.withAlpha(0.5),
        lineWidth: 4
    )

    func testRestyleOnlyChangesRequestedAspects() {
        let recolored = arrow.restyled(with: style(), aspects: .color)
        // 色だけが変わり、不透明度・太さ・矢じりは元のまま
        XCTAssertEqual(recolored.color, RGBAColor.blue.withAlpha(0.5))
        XCTAssertEqual(recolored.lineWidth, 4)
        XCTAssertEqual(recolored.shape, arrow.shape)

        let widened = arrow.restyled(with: style(), aspects: .lineWidth)
        XCTAssertEqual(widened.lineWidth, 9)
        XCTAssertEqual(widened.color, arrow.color)
    }

    func testLineWidthAppliesOnlyToTheSameTool() {
        XCTAssertEqual(arrow.restyled(with: style(), aspects: .lineWidth, lineWidthTool: .rectangle).lineWidth, 4)
        XCTAssertEqual(arrow.restyled(with: style(), aspects: .lineWidth, lineWidthTool: .arrow).lineWidth, 9)
    }

    func testEffectsIgnoreStyle() {
        let mosaic = Annotation(shape: .mosaic(CGRect(x: 0, y: 0, width: 50, height: 50)), color: .red, lineWidth: 0)
        XCTAssertEqual(mosaic.restyled(with: style()), mosaic)
    }

    func testWithFontSizeScalesRunsProportionally() {
        let text = Annotation(
            shape: .text(runs: [TextRun(text: "大", fontSize: 40), TextRun(text: "小", fontSize: 20)], origin: .zero, style: TextStyle()),
            color: .red,
            lineWidth: 0
        )
        guard case .text(let runs, _, _, _) = text.withFontSize(20).shape else { return XCTFail() }
        XCTAssertEqual(runs.map(\.fontSize), [20, 10])
        // 文字以外は変わらない
        XCTAssertEqual(arrow.withFontSize(30), arrow)
    }

    func testMultilineTextIsTallerAndKeepsLines() {
        let one = Annotation.textSize([TextRun(text: "メモ", fontSize: 20)])
        let two = Annotation.textSize([TextRun(text: "メモ\n2 行目", fontSize: 20)])
        XCTAssertGreaterThan(two.height, one.height * 1.8)
        XCTAssertEqual(Annotation.plainText([TextRun(text: "a\nb", fontSize: 20)]), "a\nb")
    }

    func testWrappedTextStaysWithinWidth() {
        let runs = [TextRun(text: "長い文字は、折り返す幅に届いたら下の行に回り込む", fontSize: 20)]
        let single = Annotation.textSize(runs)
        let wrapped = Annotation.textSize(runs, width: 100)
        XCTAssertLessThanOrEqual(wrapped.width, 100)
        XCTAssertGreaterThan(wrapped.height, single.height * 2)
        // 折り返す幅は、動かしても大きさを変えても保つ
        let text = Annotation(shape: .text(runs: runs, origin: .zero, style: TextStyle(), width: 100), color: .red, lineWidth: 0)
        guard case .text(_, _, _, let width) = text.translated(by: CGVector(dx: 3, dy: 3)).withFontSize(30).shape else { return XCTFail() }
        XCTAssertEqual(width, 100)
        XCTAssertLessThanOrEqual(text.bounds.width, 100)
    }

    func testFontFamilyFallsBackToSystemFont() {
        XCTAssertEqual(Annotation.textFont(size: 20, family: "存在しないフォント"), NSFont.boldSystemFont(ofSize: 20))
        let helvetica = Annotation.textFont(size: 20, family: "Helvetica")
        XCTAssertEqual(helvetica.familyName, "Helvetica")
        XCTAssertTrue(NSFontManager.shared.traits(of: helvetica).contains(.boldFontMask))
    }

    func testStylesWithoutFontFamilyStillDecode() throws {
        // フォントを選べるようになる前に保存したスタイルも読める
        let text = try JSONDecoder().decode(TextStyle.self, from: Data(#"{"decoration":"label","outline":0}"#.utf8))
        XCTAssertEqual(text.decoration, .label)
        XCTAssertNil(text.fontFamily)
        let counter = try JSONDecoder().decode(CounterStyle.self, from: Data(#"{"design":"plain","format":"number"}"#.utf8))
        XCTAssertNil(counter.fontFamily)
        var style = TextStyle()
        style.fontFamily = "Helvetica"
        XCTAssertEqual(try JSONDecoder().decode(TextStyle.self, from: JSONEncoder().encode(style)), style)
    }

    func testSnappedTo45KeepsLength() {
        let origin = CGPoint(x: 10, y: 10)
        // ほぼ右向きは、真横にそろう
        let right = CGPoint(x: 110, y: 18).snappedTo45(from: origin)
        XCTAssertEqual(right.y, 10, accuracy: 0.001)
        XCTAssertEqual(hypot(right.x - 10, right.y - 10), hypot(100, 8), accuracy: 0.001)
        // ほぼ斜めは、45° にそろう
        let diagonal = CGPoint(x: 60, y: 70).snappedTo45(from: origin)
        XCTAssertEqual(diagonal.x - 10, diagonal.y - 10, accuracy: 0.001)
    }

    func testPercentText() {
        XCTAssertEqual(0.8.percentText, "80%")
        XCTAssertEqual(CGFloat(1.5).percentText, "150%")
        XCTAssertEqual(0.666.percentText, "67%")
    }

    func testTranslated() {
        let moved = arrow.translated(by: CGVector(dx: 5, dy: -3))
        guard case .arrow(let from, let to, _) = moved.shape else { return XCTFail() }
        XCTAssertEqual(from, CGPoint(x: 15, y: 7))
        XCTAssertEqual(to, CGPoint(x: 115, y: 7))
        XCTAssertEqual(moved.id, arrow.id)
    }

    func testArrowHitTest() {
        XCTAssertTrue(arrow.hitTest(CGPoint(x: 60, y: 12), tolerance: 3))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 60, y: 40), tolerance: 3))
    }

    func testCodableRoundTrip() throws {
        let annotations = [
            arrow,
            Annotation(shape: .counter(3, center: CGPoint(x: 5, y: 6), radius: 14, style: CounterStyle()), color: .green, lineWidth: 0),
            Annotation(shape: .text(runs: [TextRun(text: "メモ", fontSize: 24)], origin: CGPoint(x: 1, y: 2), style: TextStyle()), color: .black, lineWidth: 0),
        ]
        let data = try JSONEncoder().encode(annotations)
        XCTAssertEqual(try JSONDecoder().decode([Annotation].self, from: data), annotations)
    }
}

/// 矢印のスタイルの保存形式（前の版の形式も読める）
final class ArrowStyleCodingTests: XCTestCase {
    private func decode(_ json: String) throws -> ArrowStyle {
        try JSONDecoder().decode(ArrowStyle.self, from: Data(json.utf8))
    }

    func testLegacyKinds() throws {
        let double = try decode(#"{"head": 2, "kind": "double"}"#)
        XCTAssertEqual(double.head, .large)
        XCTAssertTrue(double.startHead)
        XCTAssertTrue(double.endHead)

        let none = try decode(#"{"kind": "none"}"#)
        XCTAssertFalse(none.hasHeads)

        let open = try decode(#"{"kind": "open"}"#)
        XCTAssertEqual(open.shape, .open)
        XCTAssertFalse(open.startHead)
        XCTAssertTrue(open.endHead)

        // 何もなければ、終点にだけ三角の矢じり
        let empty = try decode("{}")
        XCTAssertEqual(empty, ArrowStyle())
    }

    func testRoundTrip() throws {
        var style = ArrowStyle()
        style.head = .xlarge
        style.shape = .open
        style.startHead = true
        style.endHead = false
        let data = try JSONEncoder().encode(style)
        XCTAssertEqual(try JSONDecoder().decode(ArrowStyle.self, from: data), style)
    }
}
