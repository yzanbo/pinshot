import AppKit
import XCTest

/// 一覧のキー操作の決まり（画像・文字・共有の一覧で同じ）
final class ListKeysTests: XCTestCase {
    private func action(
        _ keyCode: UInt16,
        _ key: String? = nil,
        _ modifiers: NSEvent.ModifierFlags = [],
        horizontal: Bool = true,
        vertical: Bool = true
    ) -> ListKeyAction? {
        ListKeys.action(keyCode: keyCode, key: key, modifiers: modifiers, horizontal: horizontal, vertical: vertical)
    }

    func testArrowsMoveAndShiftExtends() {
        XCTAssertEqual(action(KeyCode.rightArrow), .move(by: 1, extending: false))
        XCTAssertEqual(action(KeyCode.leftArrow), .move(by: -1, extending: false))
        XCTAssertEqual(action(KeyCode.downArrow), .move(by: 1, extending: false))
        XCTAssertEqual(action(KeyCode.upArrow, nil, .shift), .move(by: -1, extending: true))
    }

    /// サムネイルでは ↑ ↓ を扱わない（一覧のスクロールに任せる）。↓ も ↑ も同じ（前に ↓ だけ効いてしまっていた）
    func testVerticalArrowsAreLeftToScrollingInThumbnails() {
        XCTAssertNil(action(KeyCode.downArrow, vertical: false))
        XCTAssertNil(action(KeyCode.upArrow, vertical: false))
        XCTAssertEqual(action(KeyCode.rightArrow, vertical: false), .move(by: 1, extending: false))
    }

    /// 文字の一覧は縦に並ぶので、← → は扱わない（探す欄などに任せる）
    func testHorizontalArrowsCanBeIgnored() {
        XCTAssertNil(action(KeyCode.leftArrow, horizontal: false))
        XCTAssertNil(action(KeyCode.rightArrow, horizontal: false))
        XCTAssertEqual(action(KeyCode.downArrow, horizontal: false), .move(by: 1, extending: false))
    }

    func testCommandKeys() {
        XCTAssertEqual(action(0, "a", .command), .selectAll)
        XCTAssertEqual(action(0, "A", [.command, .capsLock]), .selectAll, "caps lock は見ない")
        XCTAssertEqual(action(0, "c", .command), .copy)
        XCTAssertNil(action(0, "a"), "⌘ なしの a は扱わない")
        XCTAssertNil(action(0, "c", [.command, .shift]), "⇧⌘C は扱わない")
        XCTAssertNil(action(0, "x", .command))
    }

    func testOtherKeys() {
        XCTAssertEqual(action(KeyCode.escape), .clearSelection)
        XCTAssertEqual(action(KeyCode.delete), .remove)
        XCTAssertEqual(action(KeyCode.forwardDelete), .remove)
        XCTAssertEqual(action(KeyCode.return), .activate)
        XCTAssertEqual(action(KeyCode.keypadEnter), .activate)
        XCTAssertNil(action(KeyCode.space))
    }
}
