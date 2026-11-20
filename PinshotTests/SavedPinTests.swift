import XCTest

/// 終了・再起動のあとも残す、浮かせた画像の状態
final class SavedPinTests: XCTestCase {
    private func makePin(id: UUID = UUID()) -> SavedPin {
        let arrow = Annotation(
            shape: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 40), style: ArrowStyle()),
            color: .red,
            lineWidth: 4
        )
        let text = Annotation(
            shape: .text(runs: [TextRun(text: "メモ", fontSize: 20)], origin: CGPoint(x: 5, y: 5), style: TextStyle(), width: 120),
            color: .blue,
            lineWidth: 0
        )
        return SavedPin(
            id: id,
            imageSize: CGSize(width: 400, height: 300),
            frame: CGRect(x: 100, y: 200, width: 200, height: 150),
            zoom: 0.5,
            opacity: 0.8,
            snapshot: EditSnapshot(annotations: [arrow, text], cropRect: CGRect(x: 0, y: 0, width: 400, height: 300)),
            backdrop: SavedBackdrop(shown: true, decoration: ExportDecoration(), followsSettings: false),
            onTopOverride: false
        )
    }

    func testSessionRoundTripsThroughJSON() throws {
        var session = SavedPinSession()
        session.pins = [makePin(), makePin()]
        session.closed = [makePin()]
        let decoded = try JSONDecoder().decode(SavedPinSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded, session)
        // 書き込み（矢印・折り返し幅付きの文字）・トリミング・背景・最前面の設定も残る
        XCTAssertEqual(decoded.pins[0].snapshot.annotations.count, 2)
        XCTAssertEqual(decoded.pins[0].onTopOverride, false)
    }

    func testOriginRoundTripsAndOldStateHasNone() throws {
        // どの履歴の画像かも残る（戻したあとも、履歴から同じ画像を浮かせたときに増やさないため）
        var pin = makePin()
        let historyID = UUID()
        pin.origin = .textHistory(historyID)
        let decoded = try JSONDecoder().decode(SavedPin.self, from: JSONEncoder().encode(pin))
        XCTAssertEqual(decoded.origin, .textHistory(historyID))
        XCTAssertNotEqual(decoded.origin, .captureHistory(historyID))

        // 印を足す前の版で残した状態も読める（印はなし）
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(makePin())) as? [String: Any])
        object.removeValue(forKey: "origin")
        let old = try JSONDecoder().decode(SavedPin.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.origin)
    }

    func testImageFileNamesCoverPinsAndClosed() {
        let a = UUID(), b = UUID()
        var session = SavedPinSession()
        session.pins = [makePin(id: a)]
        session.closed = [makePin(id: b)]
        XCTAssertEqual(session.imageFileNames, ["\(a.uuidString).png", "\(b.uuidString).png"])
    }
}
