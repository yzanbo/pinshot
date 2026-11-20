import XCTest

/// 一覧の JSON の読み書きの決まり（1 件ずつ読む・読めないときは元のファイルを残す）
final class StoredJSONTests: XCTestCase {
    private struct Item: Codable, Equatable {
        var id: Int
        var name: String
    }

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("StoredJSONTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    // MARK: - 1 件ずつ読む

    func testSkipsOnlyUnreadableElements() throws {
        let json = #"[{"id":1,"name":"a"},{"id":"壊れた"},{"id":3,"name":"c"}]"#
        let loaded = try XCTUnwrap(StoredJSON.decodeList(Item.self, from: Data(json.utf8)))
        XCTAssertEqual(loaded.elements, [Item(id: 1, name: "a"), Item(id: 3, name: "c")])
        XCTAssertEqual(loaded.skipped, 1)
    }

    func testNotAnArrayIsNil() {
        XCTAssertNil(StoredJSON.decodeList(Item.self, from: Data("壊れた".utf8)))
        XCTAssertNil(StoredJSON.decodeList(Item.self, from: Data(#"{"id":1}"#.utf8)))
    }

    // MARK: - ファイル

    func testMissingFileIsEmptyAndKeepsNothing() throws {
        let loaded = StoredJSON.loadList(Item.self, from: folder.appendingPathComponent("list.json"))
        XCTAssertEqual(loaded.elements, [])
        XCTAssertEqual(try files(), [])
    }

    func testReadableFileKeepsNoCopy() throws {
        let url = folder.appendingPathComponent("list.json")
        StoredJSON.write(try JSONEncoder().encode([Item(id: 1, name: "a")]), to: url)
        XCTAssertEqual(StoredJSON.loadList(Item.self, from: url).elements, [Item(id: 1, name: "a")])
        XCTAssertEqual(try files(), ["list.json"])
    }

    /// 読めない件があれば、上書きで消えないよう元のファイルを別名で残す。同じ中身なら何度読んでも 1 つだけ
    func testKeepsUnreadableFileOnce() throws {
        let url = folder.appendingPathComponent("list.json")
        let json = Data(#"[{"id":1,"name":"a"},{"id":"壊れた"}]"#.utf8)
        try json.write(to: url)
        let first = Date(timeIntervalSinceReferenceDate: 785_000_000)
        XCTAssertEqual(StoredJSON.loadList(Item.self, from: url, now: first).elements, [Item(id: 1, name: "a")])
        XCTAssertEqual(StoredJSON.loadList(Item.self, from: url, now: first.addingTimeInterval(60)).skipped, 1)
        let backup = StoredJSON.backupURL(for: url, date: first)
        XCTAssertEqual(try files(), ["list.json", backup.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: backup), json)
    }

    /// 配列として読めないファイルも、空で始める前に残す
    func testKeepsBrokenFile() throws {
        let url = folder.appendingPathComponent("list.json")
        try Data("壊れた".utf8).write(to: url)
        XCTAssertEqual(StoredJSON.loadList(Item.self, from: url).elements, [])
        XCTAssertEqual(try files().count, 2)
    }

    func testBackupName() {
        let url = URL(fileURLWithPath: "/tmp/history.json")
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 11
        components.day = 21
        components.hour = 3
        components.minute = 15
        let date = components.date!
        XCTAssertEqual(StoredJSON.backupURL(for: url, date: date).lastPathComponent, "history.unreadable-20261121-031500.json")
    }
}
