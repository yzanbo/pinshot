import XCTest

/// 一覧の選び方（画像の履歴・文字の履歴で共通）
final class ListSelectionTests: XCTestCase {
    private let ids = (0..<5).map { _ in UUID() }

    func testClickSelectsOnlyOne() {
        var selection = ListSelection()
        selection.click(ids[1], command: false, shift: false, order: ids)
        selection.click(ids[3], command: false, shift: false, order: ids)
        XCTAssertEqual(selection.selected, [ids[3]])
        XCTAssertEqual(selection.anchor, ids[3])
    }

    func testCommandClickToggles() {
        var selection = ListSelection()
        selection.click(ids[0], command: false, shift: false, order: ids)
        selection.click(ids[2], command: true, shift: false, order: ids)
        XCTAssertEqual(selection.selected, [ids[0], ids[2]])
        selection.click(ids[0], command: true, shift: false, order: ids)
        XCTAssertEqual(selection.selected, [ids[2]])
    }

    func testShiftClickSelectsRangeFromAnchor() {
        var selection = ListSelection()
        selection.click(ids[3], command: false, shift: false, order: ids)
        selection.click(ids[1], command: false, shift: true, order: ids)
        XCTAssertEqual(selection.selected, Set(ids[1...3]))
        // 起点は動かさない（続けて shift + クリックすると、同じ起点からの範囲に変わる）
        selection.click(ids[4], command: false, shift: true, order: ids)
        XCTAssertEqual(selection.selected, Set(ids[3...4]))
    }

    func testCommandShiftClickAddsRange() {
        var selection = ListSelection()
        selection.click(ids[0], command: false, shift: false, order: ids)
        selection.click(ids[3], command: true, shift: false, order: ids)
        selection.click(ids[4], command: true, shift: true, order: ids)
        XCTAssertEqual(selection.selected, [ids[0], ids[3], ids[4]])
    }

    func testMoveSelectsNeighborAndStopsAtEnds() {
        var selection = ListSelection()
        // 何も選んでいないときは、進む向きの端から
        selection.move(by: 1, extending: false, order: ids)
        XCTAssertEqual(selection.selected, [ids[0]])
        selection.move(by: -1, extending: false, order: ids)
        XCTAssertEqual(selection.selected, [ids[0]])
        selection.move(by: 1, extending: true, order: ids)
        selection.move(by: 1, extending: true, order: ids)
        XCTAssertEqual(selection.selected, Set(ids[0...2]))
    }

    func testRemoveForgetsAnchor() {
        var selection = ListSelection()
        selection.click(ids[2], command: false, shift: false, order: ids)
        selection.remove([ids[2]])
        XCTAssertTrue(selection.isEmpty)
        XCTAssertNil(selection.anchor)
    }

    func testSelectAllAndClear() {
        var selection = ListSelection()
        selection.selectAll(ids)
        XCTAssertEqual(selection.selected, Set(ids))
        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }
}

/// 読み取った文字の履歴の決まり
final class TextHistoryRulesTests: XCTestCase {
    private func entry(_ text: String, minutesAgo: Double = 0) -> RecognizedTextEntry {
        RecognizedTextEntry(id: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000 - minutesAgo * 60), text: text)
    }

    func testAddingMovesSameTextToTop() {
        let old = [entry("B", minutesAgo: 1), entry("A", minutesAgo: 2)]
        let added = TextHistoryRules.adding(entry("A"), to: old)
        XCTAssertEqual(added.map(\.text), ["A", "B"])
    }

    func testFilteredIgnoresCaseAndKana() {
        let entries = [entry("Hello World"), entry("カタカナ"), entry("別の文")]
        XCTAssertEqual(TextHistoryRules.filtered(entries, query: "hello").map(\.text), ["Hello World"])
        XCTAssertEqual(TextHistoryRules.filtered(entries, query: "かたかな").map(\.text), ["カタカナ"])
        XCTAssertEqual(TextHistoryRules.filtered(entries, query: "  ").count, 3)
    }

    func testPreviewSkipsBlankLinesAndTruncates() {
        XCTAssertEqual(TextHistoryRules.preview("\n  最初の行  \n次の行"), "最初の行")
        XCTAssertEqual(TextHistoryRules.preview(String(repeating: "あ", count: 50), maxLength: 10), String(repeating: "あ", count: 10) + "…")
    }

    func testCountAndSummaryText() {
        XCTAssertEqual(TextHistoryRules.countText("abc"), "3 文字")
        XCTAssertEqual(TextHistoryRules.countText("ab\ncd"), "5 文字・2 行")
        XCTAssertEqual(TextHistoryRules.summaryText(count: 0), "なし")
        XCTAssertEqual(TextHistoryRules.summaryText(count: 4), "4 件")
    }

    func testJoinedKeepsOrder() {
        XCTAssertEqual(TextHistoryRules.joined([entry("一"), entry("二")]), "一\n\n二")
    }

    func testDecodesEntriesWithoutImage() throws {
        // 画像を残す前の版の履歴も読める（画像のファイル名と大きさは nil）
        let json = #"[{"id":"7C0D2F0E-1B7A-4C55-9C2B-0F5E8B7C1A11","date":0,"text":"前の版"}]"#
        let entries = try JSONDecoder().decode([RecognizedTextEntry].self, from: Data(json.utf8))
        XCTAssertEqual(entries.first?.text, "前の版")
        XCTAssertNil(entries.first?.imageFileName)
        XCTAssertNil(entries.first?.pointSize)
    }

    func testImageFileNameUsesID() {
        let id = UUID()
        XCTAssertEqual(RecognizedTextEntry.imageFileName(for: id), "\(id.uuidString).text.png")
    }

    func testExpiredWorksForTexts() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [entry("新しい"), entry("古い", minutesAgo: 60 * 24 * 2)]
        let expired = CaptureHistoryRules.expired(entries, now: now, period: .day, limit: .fifty)
        XCTAssertEqual(expired.map(\.text), ["古い"])
    }
}
