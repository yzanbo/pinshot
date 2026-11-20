import XCTest

/// 保存する形を固定するテスト（いまの版が書いた JSON を、決まった文字列として持ち、読めることを確かめる）。
/// 書き込みの種類・項目の名前を変えると、前の版が書いた浮かせた画像や履歴を読めなくなるので、ここで気づけるようにする。
/// 形を変えるときは、前の形を読み替えて引き継ぐ（このテストの JSON は書き換えず、新しい形のテストを足す）
final class StoredFormatTests: XCTestCase {
    // MARK: - 決まった値

    static let date = Date(timeIntervalSinceReferenceDate: 785_000_000)
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    /// 11 種類の書き込みを 1 つずつ
    static var annotations: [Annotation] {
        let red = RGBAColor.red
        var arrow = ArrowStyle()
        arrow.startHead = true
        return [
            Annotation(id: id(1), shape: .rectangle(CGRect(x: 1, y: 2, width: 30, height: 40), style: ShapeStyle(corner: .small, fill: .translucent)), color: red, lineWidth: 4),
            Annotation(id: id(2), shape: .ellipse(CGRect(x: 5, y: 6, width: 70, height: 80), style: ShapeStyle()), color: red, lineWidth: 2),
            Annotation(id: id(3), shape: .arrow(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 50, y: 60), style: arrow), color: red, lineWidth: 4),
            Annotation(id: id(4), shape: .pen([CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 4)]), color: red, lineWidth: 4),
            Annotation(id: id(5), shape: .highlight([CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 20)]), color: .yellow, lineWidth: 18),
            Annotation(id: id(6), shape: .textMark([CGRect(x: 10, y: 10, width: 100, height: 14)], style: TextMarkStyle(kind: .underline, padding: .small, linePosition: .lower)), color: red, lineWidth: 2),
            Annotation(id: id(7), shape: .text(runs: [TextRun(text: "見本", fontSize: 24), TextRun(text: "Aa", fontSize: 12)], origin: CGPoint(x: 8, y: 9), style: TextStyle(decoration: .whiteOutline, outline: .thick, fontFamily: "Hiragino Sans", marker: .highlight, markerColor: .green), width: 200), color: red, lineWidth: 4),
            Annotation(id: id(8), shape: .counter(3, center: CGPoint(x: 40, y: 50), radius: 14, style: CounterStyle(design: .outlineCircle, format: .letter, fontFamily: nil)), color: .blue, lineWidth: 4),
            Annotation(id: id(9), shape: .mosaic(CGRect(x: 0, y: 0, width: 20, height: 20)), color: red, lineWidth: 4),
            Annotation(id: id(10), shape: .blur(CGRect(x: 20, y: 20, width: 20, height: 20)), color: red, lineWidth: 4),
            Annotation(id: id(11), shape: .spotlight(CGRect(x: 40, y: 40, width: 20, height: 20)), color: red, lineWidth: 4),
        ]
    }

    static var session: SavedPinSession {
        let pin = SavedPin(
            id: id(100),
            imageSize: CGSize(width: 320, height: 200),
            frame: CGRect(x: 100, y: 200, width: 320, height: 200),
            zoom: 1,
            opacity: 0.8,
            snapshot: EditSnapshot(annotations: Array(annotations.prefix(2)), cropRect: CGRect(x: 0, y: 0, width: 320, height: 200)),
            backdrop: SavedBackdrop(shown: true, decoration: ExportDecoration(), followsSettings: false),
            onTopOverride: false,
            origin: .captureHistory(id(200))
        )
        return SavedPinSession(pins: [pin], closed: [])
    }

    static var captureEntry: CaptureHistoryEntry {
        CaptureHistoryEntry(id: id(300), date: date, pointSize: CGSize(width: 320, height: 200), pixelSize: CGSize(width: 640, height: 400), byteCount: 12345)
    }

    static var uploadEntry: UploadHistoryEntry {
        UploadHistoryEntry(
            id: id(400),
            date: date,
            remote: RemoteFile(destination: .gyazo, id: "abc123", info: ["url": "https://i.gyazo.com/abc123.png"]),
            link: SharedLink(pageURL: URL(string: "https://gyazo.com/abc123")!, directURL: URL(string: "https://i.gyazo.com/abc123.png")),
            kind: .image,
            fileName: "Pinshot.png"
        )
    }

    // MARK: - いまの版が書いた JSON（書き換えない）

    static let annotationJSON = [
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000001","lineWidth":4,"shape":{"rectangle":{"_0":[[1,2],[30,40]],"style":{"corner":1,"fill":"translucent"}}}}"#,
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000002","lineWidth":2,"shape":{"ellipse":{"_0":[[5,6],[70,80]],"style":{"corner":0,"fill":"none"}}}}"#,
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000003","lineWidth":4,"shape":{"arrow":{"from":[1,1],"style":{"endHead":true,"head":1,"shape":"filled","startHead":true},"to":[50,60]}}}"#,
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000004","lineWidth":4,"shape":{"pen":{"_0":[[1,2],[3,4]]}}}"#,
        #"{"color":{"a":1,"b":0,"g":0.8,"r":1},"id":"00000000-0000-0000-0000-000000000005","lineWidth":18,"shape":{"highlight":{"_0":[[10,20],[30,20]]}}}"#,
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000006","lineWidth":2,"shape":{"textMark":{"_0":[[[10,10],[100,14]]],"style":{"kind":"underline","linePosition":2,"padding":"small"}}}}"#,
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000007","lineWidth":4,"shape":{"text":{"origin":[8,9],"runs":[{"fontSize":24,"text":"見本"},{"fontSize":12,"text":"Aa"}],"style":{"decoration":"whiteOutline","fontFamily":"Hiragino Sans","marker":"highlight","markerColor":{"a":1,"b":0.349,"g":0.78,"r":0.204},"outline":2},"width":200}}}"#,
        #"{"color":{"a":1,"b":1,"g":0.478,"r":0},"id":"00000000-0000-0000-0000-000000000008","lineWidth":4,"shape":{"counter":{"_0":3,"center":[40,50],"radius":14,"style":{"design":"outlineCircle","format":"letter"}}}}"#,
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000009","lineWidth":4,"shape":{"mosaic":{"_0":[[0,0],[20,20]]}}}"#,
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000010","lineWidth":4,"shape":{"blur":{"_0":[[20,20],[20,20]]}}}"#,
        #"{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000011","lineWidth":4,"shape":{"spotlight":{"_0":[[40,40],[20,20]]}}}"#,
    ]

    static let sessionJSON = #"{"closed":[],"pins":[{"backdrop":{"decoration":{"background":"ocean","corner":1,"isEnabled":false,"padding":1,"shadow":true},"followsSettings":false,"shown":true},"frame":[[100,200],[320,200]],"id":"00000000-0000-0000-0000-000000000100","imageSize":[320,200],"onTopOverride":false,"opacity":0.8,"origin":{"captureHistory":{"_0":"00000000-0000-0000-0000-000000000200"}},"snapshot":{"annotations":[{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000001","lineWidth":4,"shape":{"rectangle":{"_0":[[1,2],[30,40]],"style":{"corner":1,"fill":"translucent"}}}},{"color":{"a":1,"b":0.188,"g":0.231,"r":1},"id":"00000000-0000-0000-0000-000000000002","lineWidth":2,"shape":{"ellipse":{"_0":[[5,6],[70,80]],"style":{"corner":0,"fill":"none"}}}}],"cropRect":[[0,0],[320,200]]},"zoom":1}],"version":1}"#

    static let captureEntryJSON = #"{"byteCount":12345,"date":785000000,"id":"00000000-0000-0000-0000-000000000300","pixelSize":[640,400],"pointSize":[320,200]}"#

    static let uploadEntryJSON = #"{"date":785000000,"fileName":"Pinshot.png","id":"00000000-0000-0000-0000-000000000400","kind":"image","link":{"directURL":"https:\/\/i.gyazo.com\/abc123.png","pageURL":"https:\/\/gyazo.com\/abc123"},"remote":{"destination":"gyazo","id":"abc123","info":{"url":"https:\/\/i.gyazo.com\/abc123.png"}}}"#

    // MARK: - 読めるか

    func testReadsEveryAnnotationKind() throws {
        XCTAssertEqual(Self.annotationJSON.count, 11, "書き込みの種類ごとに 1 つずつ")
        for (json, expected) in zip(Self.annotationJSON, Self.annotations) {
            XCTAssertEqual(try JSONDecoder().decode(Annotation.self, from: Data(json.utf8)), expected)
        }
    }

    func testReadsSavedPinSession() throws {
        let decoded = try XCTUnwrap(SavedPinSession.decode(from: Data(Self.sessionJSON.utf8)))
        XCTAssertEqual(decoded.session, Self.session)
        XCTAssertEqual(decoded.skipped, 0)
        XCTAssertFalse(decoded.losesData)
    }

    func testReadsHistoryEntries() throws {
        XCTAssertEqual(try JSONDecoder().decode(CaptureHistoryEntry.self, from: Data(Self.captureEntryJSON.utf8)), Self.captureEntry)
        XCTAssertEqual(try JSONDecoder().decode(UploadHistoryEntry.self, from: Data(Self.uploadEntryJSON.utf8)), Self.uploadEntry)
    }

    // MARK: - 読めないものがあるとき

    /// 知らない書き込みの種類（新しい版で足したものなど）を含む画像だけを飛ばし、ほかは読む
    func testSkipsOnlyUnreadablePins() throws {
        let unknown = #"{"color":{"a":1,"b":0,"g":0,"r":1},"id":"00000000-0000-0000-0000-000000000099","lineWidth":4,"shape":{"stamp":{"_0":[1,2]}}}"#
        let pin = Self.sessionJSON.components(separatedBy: #""pins":["#)[1].components(separatedBy: #"],"version""#)[0]
        let broken = pin.replacingOccurrences(of: #""annotations":["#, with: #""annotations":["# + unknown + ",")
        let json = #"{"closed":["# + broken + #"],"pins":["# + pin + #"],"version":1}"#
        let decoded = try XCTUnwrap(SavedPinSession.decode(from: Data(json.utf8)))
        XCTAssertEqual(decoded.session.pins, Self.session.pins)
        XCTAssertEqual(decoded.session.closed, [])
        XCTAssertEqual(decoded.skipped, 1)
        XCTAssertTrue(decoded.losesData, "飛ばしたものがあれば、上書きする前に元のファイルを残す")
    }

    /// 新しい版が書いたもの（version が大きい）は、読めても上書きする前に残す（この版が知らない項目が消えるため）
    func testNewerVersionIsKeptBeforeOverwriting() throws {
        let json = Self.sessionJSON.replacingOccurrences(of: #""version":1"#, with: #""version":2"#)
        let decoded = try XCTUnwrap(SavedPinSession.decode(from: Data(json.utf8)))
        XCTAssertEqual(decoded.session.pins, Self.session.pins)
        XCTAssertTrue(decoded.isNewer)
        XCTAssertTrue(decoded.losesData)
        XCTAssertEqual(decoded.session.version, SavedPinSession.currentVersion, "書き直すときは、この版の形の番号にする")
    }

    func testUnreadableSessionIsNil() {
        XCTAssertNil(SavedPinSession.decode(from: Data("壊れた".utf8)))
    }
}
