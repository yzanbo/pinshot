import AppKit
import XCTest

/// 文字の読み取り（並べ方と、実際に Vision で読めるか）
final class TextRecognizerTests: XCTestCase {
    private func piece(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.2, height: CGFloat = 0.05) -> RecognizedText {
        RecognizedText(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    func testJoinsTopToBottomAndLeftToRight() {
        // Vision の座標は左下が原点なので、y が大きいほど上の行
        let pieces = [
            piece("2 行目", x: 0.1, y: 0.5),
            piece("右", x: 0.6, y: 0.8),
            piece("1 行目", x: 0.1, y: 0.8),
        ]
        XCTAssertEqual(RecognizedTextLayout.join(pieces), "1 行目右\n2 行目")
    }

    func testSpacesOnlyBetweenAlphanumerics() {
        XCTAssertTrue(RecognizedTextLayout.needsSpace(between: "Hello", and: "World"))
        XCTAssertFalse(RecognizedTextLayout.needsSpace(between: "こんにちは", and: "世界"))
        XCTAssertFalse(RecognizedTextLayout.needsSpace(between: "Pinshot", and: "の使い方"))
        let pieces = [piece("Hello", x: 0.1, y: 0.5), piece("World", x: 0.4, y: 0.51)]
        XCTAssertEqual(RecognizedTextLayout.join(pieces), "Hello World")
    }

    func testEmptyInputGivesEmptyText() {
        XCTAssertEqual(RecognizedTextLayout.join([]), "")
        XCTAssertEqual(TextRecognizer.resultMessage(copiedCount: 0), "文字が見つかりませんでした")
        XCTAssertEqual(TextRecognizer.resultMessage(copiedCount: 12), "✓ 文字をコピーしました（12 文字）")
    }

    func testImageRectFlipsVisionCoordinates() {
        // 読んだ範囲は画像の (100, 50) から 200×100。Vision の左下 (0, 0)〜(0.5, 0.2) は、範囲の左下の部分
        let rect = RecognizedTextLayout.imageRect(for: CGRect(x: 0, y: 0, width: 0.5, height: 0.2), in: CGRect(x: 100, y: 50, width: 200, height: 100))
        XCTAssertEqual(rect, CGRect(x: 100, y: 130, width: 100, height: 20))
    }

    /// 文字を描いた画像を、実際に Vision で読む（ネットにはつながない）。
    /// Vision を使えない環境（機械学習のモデルを置けない砂場など）では飛ばす
    func testRecognizesRenderedText() throws {
        let image = try XCTUnwrap(renderedText("Pinshot 2026"))
        let text: String
        do {
            text = try TextRecognizer.recognizeText(image)
        } catch {
            throw XCTSkip("この環境では Vision の文字の読み取りを使えません: \(error)")
        }
        XCTAssertTrue(text.contains("Pinshot"), "読み取った文字: \(text)")
        XCTAssertTrue(text.contains("2026"), "読み取った文字: \(text)")
    }

    private func renderedText(_ text: String) -> CGImage? {
        let size = NSSize(width: 600, height: 160)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            (text as NSString).draw(at: NSPoint(x: 30, y: 50), withAttributes: [
                .font: NSFont.systemFont(ofSize: 56, weight: .semibold),
                .foregroundColor: NSColor.black,
            ])
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
