import XCTest

/// 元に戻す・やり直すの履歴
final class EditHistoryTests: XCTestCase {
    private func snapshot(_ width: CGFloat) -> EditSnapshot {
        EditSnapshot(annotations: [], cropRect: CGRect(x: 0, y: 0, width: width, height: 10))
    }

    func testUndoReturnsPreviousAndRedoRestores() {
        var history = EditHistory()
        XCTAssertFalse(history.canUndo)
        history.record(snapshot(1))
        XCTAssertTrue(history.canUndo)

        XCTAssertEqual(history.undo(current: snapshot(2)), snapshot(1))
        XCTAssertFalse(history.canUndo)
        XCTAssertTrue(history.canRedo)

        XCTAssertEqual(history.redo(current: snapshot(1)), snapshot(2))
        XCTAssertTrue(history.canUndo)
        XCTAssertFalse(history.canRedo)
    }

    func testRecordingClearsRedo() {
        var history = EditHistory()
        history.record(snapshot(1))
        _ = history.undo(current: snapshot(2))
        XCTAssertTrue(history.canRedo)
        history.record(snapshot(1))
        XCTAssertFalse(history.canRedo)
    }

    func testUndoWithEmptyHistoryReturnsNil() {
        var history = EditHistory()
        XCTAssertNil(history.undo(current: snapshot(1)))
        XCTAssertNil(history.redo(current: snapshot(1)))
    }
}
