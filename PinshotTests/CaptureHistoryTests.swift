import XCTest

/// 撮った画像の履歴の決まり（残し方・縮小画像の大きさ・日付ごとのまとめ方）
final class CaptureHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(hoursAgo: Double) -> CaptureHistoryEntry {
        CaptureHistoryEntry(
            id: UUID(),
            date: now.addingTimeInterval(-hoursAgo * 3600),
            pointSize: CGSize(width: 100, height: 50),
            pixelSize: CGSize(width: 200, height: 100),
            byteCount: 1000
        )
    }

    func testRemovesEntriesOlderThanPeriod() {
        let entries = [entry(hoursAgo: 1), entry(hoursAgo: 23), entry(hoursAgo: 25), entry(hoursAgo: 24 * 40)]
        let expired = CaptureHistoryRules.expired(entries, now: now, period: .day, limit: .thousand)
        XCTAssertEqual(expired, Array(entries[2...]))
        // ずっと残すときは、期間では消さない
        XCTAssertTrue(CaptureHistoryRules.expired(entries, now: now, period: .forever, limit: .thousand).isEmpty)
    }

    func testRemovesOldestBeyondLimit() {
        let entries = (0..<60).map { entry(hoursAgo: Double($0)) }
        let expired = CaptureHistoryRules.expired(entries, now: now, period: .forever, limit: .fifty)
        XCTAssertEqual(expired, Array(entries[50...]))
    }

    func testLimitCountsOnlyEntriesWithinPeriod() {
        // 期間を過ぎたものは、枚数に数えない
        let entries = [entry(hoursAgo: 1), entry(hoursAgo: 24 * 31)] + (0..<50).map { _ in entry(hoursAgo: 2) }
        let expired = CaptureHistoryRules.expired(entries, now: now, period: .month, limit: .fifty)
        XCTAssertEqual(expired.count, 2)
        XCTAssertTrue(expired.contains(entries[1]))
    }

    func testThumbnailSizeKeepsAspectAndNeverEnlarges() {
        XCTAssertEqual(CaptureHistoryRules.thumbnailSize(for: CGSize(width: 1920, height: 1080), maxSide: 480), CGSize(width: 480, height: 270))
        XCTAssertEqual(CaptureHistoryRules.thumbnailSize(for: CGSize(width: 100, height: 3000), maxSide: 480), CGSize(width: 16, height: 480))
        XCTAssertEqual(CaptureHistoryRules.thumbnailSize(for: CGSize(width: 120, height: 80), maxSide: 480), CGSize(width: 120, height: 80))
    }

    func testGroupsByDayNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let entries = [entry(hoursAgo: 30), entry(hoursAgo: 1), entry(hoursAgo: 2), entry(hoursAgo: 60)]
        let groups = CaptureHistoryRules.groupedByDay(entries, calendar: calendar)
        XCTAssertEqual(groups.map(\.entries.count).reduce(0, +), 4)
        XCTAssertEqual(groups.first?.entries.first, entries[1])
        XCTAssertTrue(zip(groups, groups.dropFirst()).allSatisfy { $0.day > $1.day })
    }

    func testDayTitle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(CaptureHistoryRules.dayTitle(now, now: now, calendar: calendar), "今日")
        XCTAssertEqual(CaptureHistoryRules.dayTitle(now.addingTimeInterval(-86400), now: now, calendar: calendar), "昨日")
    }

    func testTextHelpers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let sample = entry(hoursAgo: 0)
        XCTAssertEqual(CaptureHistoryRules.sizeText(sample), "100×50")
        XCTAssertEqual(CaptureHistoryRules.summaryText(count: 0, bytes: 0), "なし")
        XCTAssertTrue(CaptureHistoryRules.summaryText(count: 3, bytes: 2048).hasPrefix("3 枚・"))
        // 2027-01-15 17:00 +0900
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(CaptureHistoryRules.timeText(time, calendar: calendar), "17:00")
        XCTAssertEqual(CaptureHistoryRules.shortTitle(sample, now: now, calendar: calendar), "今日 17:00・100×50")
        // 日付と時刻だけ（文字の履歴の右の欄で使う）。前の日は「昨日」
        XCTAssertEqual(CaptureHistoryRules.dateTimeText(time, now: now, calendar: calendar), "今日 17:00")
        XCTAssertEqual(CaptureHistoryRules.dateTimeText(time.addingTimeInterval(-86_400), now: now, calendar: calendar), "昨日 17:00")
    }

    func testEntryRoundTripsThroughJSON() throws {
        let original = entry(hoursAgo: 3)
        let decoded = try JSONDecoder().decode(CaptureHistoryEntry.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(original.imageFileName, "\(original.id.uuidString).png")
    }
}
