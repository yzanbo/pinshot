import XCTest

/// 編集データ（書き込み・トリミング・元に戻す履歴）の決まり
final class AnnotationDocumentTests: XCTestCase {
    private let imageSize = CGSize(width: 400, height: 300)

    private func rectangle(_ x: CGFloat = 10, color: RGBAColor = .red) -> Annotation {
        Annotation(shape: .rectangle(CGRect(x: x, y: 10, width: 50, height: 40), style: ShapeStyle()), color: color, lineWidth: 4)
    }

    private func counter(_ number: Int, x: CGFloat) -> Annotation {
        Annotation(shape: .counter(number, center: CGPoint(x: x, y: 50), radius: 14, style: CounterStyle()), color: .red, lineWidth: 0)
    }

    private func recolor(_ color: RGBAColor) -> (Annotation) -> Annotation {
        { annotation in
            var copy = annotation
            copy.color = color
            return copy
        }
    }

    // MARK: - 足す・元に戻す・やり直す

    func testAddUndoRedo() {
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle()
        document.add(rect)
        XCTAssertEqual(document.annotations, [rect])
        XCTAssertTrue(document.canUndo)

        XCTAssertTrue(document.undo())
        XCTAssertTrue(document.annotations.isEmpty)
        XCTAssertTrue(document.canRedo)

        XCTAssertTrue(document.redo())
        XCTAssertEqual(document.annotations, [rect])
        XCTAssertFalse(document.redo())
    }

    // MARK: - 番号

    func testRemovingCounterRenumbersTheRest() {
        var document = AnnotationDocument(imageSize: imageSize)
        let one = counter(1, x: 10), two = counter(2, x: 50), three = counter(3, x: 90)
        [one, two, three].forEach { document.add($0) }

        XCTAssertTrue(document.remove(ids: [two.id]))
        XCTAssertEqual(document.annotations.compactMap(\.counterNumber), [1, 2])
        XCTAssertEqual(document.annotations.map(\.id), [one.id, three.id])
        XCTAssertEqual(document.nextCounterNumber, 3)

        // 元に戻すと、番号も元どおり
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations.compactMap(\.counterNumber), [1, 2, 3])
    }

    func testRemovingUnknownIDsDoesNothing() {
        var document = AnnotationDocument(imageSize: imageSize)
        document.add(rectangle())
        XCTAssertFalse(document.remove(ids: [UUID()]))
        XCTAssertEqual(document.annotations.count, 1)
    }

    func testDuplicateUsesNextCounterNumbersAndKeepsOrder() {
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle(), one = counter(1, x: 10)
        document.add(rect)
        document.add(one)

        // 選んだ順ではなく、重なり順に複製する
        let newIDs = document.duplicate(ids: [one.id, rect.id], offset: CGVector(dx: 12, dy: 12))
        XCTAssertEqual(newIDs.count, 2)
        XCTAssertEqual(document.annotations.count, 4)
        XCTAssertEqual(document.annotations[2].tool, .rectangle)
        XCTAssertEqual(document.annotations[3].counterNumber, 2)
        XCTAssertEqual(document.annotations[2].bounds.minX, rect.bounds.minX + 12, accuracy: 0.001)

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations.count, 2)
    }

    // MARK: - 重なり順

    func testReorder() {
        var document = AnnotationDocument(imageSize: imageSize)
        let a = rectangle(10), b = rectangle(20), c = rectangle(30)
        [a, b, c].forEach { document.add($0) }

        XCTAssertTrue(document.reorder(ids: [a.id], forward: true))
        XCTAssertEqual(document.annotations.map(\.id), [b.id, a.id, c.id])

        // いちばん前面のものは、それ以上前に出ない（履歴にも積まない）
        let before = document.snapshot
        XCTAssertFalse(document.reorder(ids: [c.id], forward: true))
        XCTAssertEqual(document.snapshot, before)

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations.map(\.id), [a.id, b.id, c.id])
    }

    // MARK: - 色などを続けて変える

    func testContinuousUpdatesAreCoalesced() {
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle()
        document.add(rect)
        let start = Date()

        XCTAssertTrue(document.update(ids: [rect.id], now: start, recolor(.yellow)))
        XCTAssertTrue(document.update(ids: [rect.id], now: start.addingTimeInterval(0.5), recolor(.green)))

        // 1 回の「元に戻す」で、変える前の色に戻る
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations.first?.color, .red)
    }

    func testUpdateAfterUndoIsRecorded() {
        // 黄に変える → 元に戻す（赤）→ 1 秒以内に緑に変える、で緑が履歴に残り、黄はやり直せなくなる
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle()
        document.add(rect)
        let start = Date()

        document.update(ids: [rect.id], now: start, recolor(.yellow))
        XCTAssertTrue(document.undo())
        XCTAssertTrue(document.update(ids: [rect.id], now: start.addingTimeInterval(0.3), recolor(.green)))
        XCTAssertFalse(document.canRedo)

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations.first?.color, .red)
        XCTAssertTrue(document.redo())
        XCTAssertEqual(document.annotations.first?.color, .green)
    }

    func testUpdateAfterAnotherChangeIsNotCoalesced() {
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle()
        document.add(rect)
        let start = Date()

        document.update(ids: [rect.id], now: start, recolor(.yellow))
        document.translate(ids: [rect.id], by: CGVector(dx: 5, dy: 0))
        document.update(ids: [rect.id], now: start.addingTimeInterval(0.2), recolor(.green))

        // 1 回目の元に戻すは、2 回目の色だけを戻す（動かしたぶんは残る）
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations.first?.color, .yellow)
        XCTAssertEqual(document.annotations.first?.bounds.minX ?? 0, rect.bounds.minX + 5, accuracy: 0.001)
    }

    func testUpdateWithoutChangesIsNotRecorded() {
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle()
        document.add(rect)
        XCTAssertFalse(document.update(ids: [rect.id], recolor(.red)))
        XCTAssertTrue(document.undo())
        XCTAssertFalse(document.canUndo)
    }

    // MARK: - トリミング

    func testCrop() {
        var document = AnnotationDocument(imageSize: imageSize)
        let full = CGRect(origin: .zero, size: imageSize)

        // 範囲の外にはみ出したぶんは切り捨てる
        let old = document.crop(to: CGRect(x: 100, y: 50, width: 500, height: 100))
        XCTAssertEqual(old, full)
        XCTAssertEqual(document.cropRect, CGRect(x: 100, y: 50, width: 300, height: 100))

        // 小さすぎるときはしない
        XCTAssertNil(document.crop(to: CGRect(x: 120, y: 60, width: 4, height: 4)))

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.cropRect, full)
    }

    // MARK: - ドラッグ・文字の直し

    func testChangeIsRecordedOnceWhenKept() {
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle()
        document.add(rect)

        document.beginChange()
        for dx in stride(from: 1, through: 10, by: 1) {
            document.replace(rect.translated(by: CGVector(dx: CGFloat(dx), dy: 0)))
        }
        document.endChange(keep: true)

        // 1 回の元に戻すで、動かす前に戻る
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations, [rect])
    }

    func testChangeIsRevertedWhenNotKept() {
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle()
        document.add(rect)

        document.beginChange()
        _ = document.takeOut(at: 0)
        XCTAssertTrue(document.annotations.isEmpty)
        document.endChange(keep: false)

        XCTAssertEqual(document.annotations, [rect])
        // 戻したので、元に戻すのは「足した」ことだけ
        XCTAssertTrue(document.undo())
        XCTAssertFalse(document.canUndo)
    }

    func testChangeWithoutDifferenceIsNotRecorded() {
        var document = AnnotationDocument(imageSize: imageSize)
        document.add(rectangle())
        document.beginChange()
        document.endChange(keep: true)
        XCTAssertTrue(document.undo())
        XCTAssertFalse(document.canUndo)
    }

    func testReEditKeepsPosition() {
        var document = AnnotationDocument(imageSize: imageSize)
        let a = rectangle(10), b = rectangle(20), c = rectangle(30)
        [a, b, c].forEach { document.add($0) }

        document.beginChange()
        var edited = document.takeOut(at: 1)
        edited.color = .blue
        document.insert(edited, at: 1)
        document.endChange(keep: true)
        XCTAssertEqual(document.annotations.map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(document.annotations[1].color, .blue)

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations[1].color, .red)
    }

    func testRecordingDuringChangeKeepsBothSteps() {
        var document = AnnotationDocument(imageSize: imageSize)
        let rect = rectangle()
        document.add(rect)

        document.beginChange()
        document.replace(rect.translated(by: CGVector(dx: 10, dy: 0)))
        // 変更が終わる前にほかの変更をしても、動かしたことは別の 1 回として残る
        document.add(rectangle(100))

        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations.count, 1)
        XCTAssertEqual(document.annotations[0].bounds.minX, rect.bounds.minX + 10, accuracy: 0.001)
        XCTAssertTrue(document.undo())
        XCTAssertEqual(document.annotations, [rect])
    }

    func testRestoreDoesNotTouchHistory() {
        var document = AnnotationDocument(imageSize: imageSize)
        let snapshot = EditSnapshot(annotations: [rectangle()], cropRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        document.restore(snapshot)
        XCTAssertEqual(document.snapshot, snapshot)
        XCTAssertFalse(document.canUndo)
    }
}
