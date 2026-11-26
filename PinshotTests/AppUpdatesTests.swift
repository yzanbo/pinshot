import XCTest

/// テスト用の、更新を受け持つもの（呼ばれたことを覚える）
@MainActor
private final class FakeUpdateService: AppUpdateService {
    var checksAutomatically = true
    var canCheck = true
    var lastCheckDate: Date?
    var checkCount = 0

    func checkForUpdates() {
        checkCount += 1
    }
}

/// アプリの更新の状態（設定の「一般」とメニューバーに出す。更新そのものは Sparkle が受け持つ）
@MainActor
final class AppUpdatesTests: XCTestCase {
    /// 受け持つものをつなぐまでは、更新の機能を使えない（確かめても何も起きない）
    func testUnavailableWithoutService() {
        let updates = AppUpdates()
        XCTAssertFalse(updates.isAvailable)
        XCTAssertFalse(updates.canCheck)
        updates.check()
        updates.setChecksAutomatically(true)
        XCTAssertFalse(updates.checksAutomatically)
    }

    /// つなぐと使えるようになり、受け持つものの状態を読む
    func testReadsStateOnAttach() {
        let service = FakeUpdateService()
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        service.lastCheckDate = checked
        let updates = AppUpdates()

        updates.attach(service)
        XCTAssertTrue(updates.isAvailable)
        XCTAssertTrue(updates.checksAutomatically)
        XCTAssertTrue(updates.canCheck)
        XCTAssertEqual(updates.lastCheckDate, checked)
        withExtendedLifetime(service) {}
    }

    /// 自動で確かめるかの切り替えを、受け持つものに伝える
    func testTogglesAutomaticChecks() {
        let service = FakeUpdateService()
        let updates = AppUpdates()
        updates.attach(service)

        updates.setChecksAutomatically(false)
        XCTAssertFalse(service.checksAutomatically)
        XCTAssertFalse(updates.checksAutomatically)

        updates.setChecksAutomatically(true)
        XCTAssertTrue(service.checksAutomatically)
        XCTAssertTrue(updates.checksAutomatically)
    }

    /// 確かめるように頼むと、受け持つものが確かめる
    func testForwardsCheck() {
        let service = FakeUpdateService()
        let updates = AppUpdates()
        updates.attach(service)

        updates.check()
        XCTAssertEqual(service.checkCount, 1)
    }

    /// 受け持つものの状態が変わったら、聞き直して反映する
    func testRefreshesState() {
        let service = FakeUpdateService()
        let updates = AppUpdates()
        updates.attach(service)

        service.canCheck = false
        let checked = Date(timeIntervalSince1970: 1_800_000_500)
        service.lastCheckDate = checked
        updates.refresh()
        XCTAssertFalse(updates.canCheck)
        XCTAssertEqual(updates.lastCheckDate, checked)
    }

    /// 自動で見つけた新しい版を覚え、見てもらったら忘れる（変わったときだけ知らせる）
    func testTracksPendingVersion() {
        let updates = AppUpdates()
        var notified: [String?] = []
        updates.onPendingVersionChange = { notified.append($0) }

        updates.noteUpdateFound(version: "0.5.1")
        XCTAssertEqual(updates.pendingVersion, "0.5.1")
        // 同じ版をもう一度見つけても、知らせ直さない
        updates.noteUpdateFound(version: "0.5.1")
        updates.clearPendingUpdate()
        XCTAssertNil(updates.pendingVersion)
        // もう忘れているので、知らせ直さない
        updates.clearPendingUpdate()

        XCTAssertEqual(notified, ["0.5.1", nil])
    }
}
