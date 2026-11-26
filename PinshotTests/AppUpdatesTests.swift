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
    /// テストごとに別の保存場所を作る（ふだんの設定に触れないように。テストが終わったら消す）
    private func makeDefaults() -> UserDefaults {
        let suite = "AppUpdatesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// 受け持つものをつなぐまでは、更新の機能を使えない（確かめても何も起きない）
    func testUnavailableWithoutService() {
        let updates = AppUpdates(defaults: makeDefaults(), currentBuild: "7")
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
        let updates = AppUpdates(defaults: makeDefaults(), currentBuild: "7")

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
        let updates = AppUpdates(defaults: makeDefaults(), currentBuild: "7")
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
        let updates = AppUpdates(defaults: makeDefaults(), currentBuild: "7")
        updates.attach(service)

        updates.check()
        XCTAssertEqual(service.checkCount, 1)
    }

    /// 受け持つものの状態が変わったら、聞き直して反映する
    func testRefreshesState() {
        let service = FakeUpdateService()
        let updates = AppUpdates(defaults: makeDefaults(), currentBuild: "7")
        updates.attach(service)

        service.canCheck = false
        let checked = Date(timeIntervalSince1970: 1_800_000_500)
        service.lastCheckDate = checked
        updates.refresh()
        XCTAssertFalse(updates.canCheck)
        XCTAssertEqual(updates.lastCheckDate, checked)
    }

    /// 見つけた新しい版を覚え、片付いたら忘れる（変わったときだけ知らせる）
    func testTracksPendingVersion() {
        let updates = AppUpdates(defaults: makeDefaults(), currentBuild: "7")
        var notified: [String?] = []
        updates.onPendingVersionChange = { notified.append($0) }

        updates.noteUpdateFound(version: "0.5.1", build: "8")
        XCTAssertEqual(updates.pendingVersion, "0.5.1")
        // 同じ版をもう一度見つけても、知らせ直さない
        updates.noteUpdateFound(version: "0.5.1", build: "8")
        updates.clearPendingUpdate()
        XCTAssertNil(updates.pendingVersion)
        // もう忘れているので、知らせ直さない
        updates.clearPendingUpdate()

        XCTAssertEqual(notified, ["0.5.1", nil])
    }

    /// 見つけた版は、終了して起動し直しても、まだ入れていなければ印を戻す
    func testRestoresPendingUpdateAfterRelaunch() {
        let defaults = makeDefaults()
        AppUpdates(defaults: defaults, currentBuild: "7").noteUpdateFound(version: "0.5.1", build: "8")

        let relaunched = AppUpdates(defaults: defaults, currentBuild: "7")
        XCTAssertEqual(relaunched.pendingVersion, "0.5.1")
    }

    /// 見つけた版を入れて開き直したら（今の版が同じか新しい）、印を戻さず、保存も消す
    func testForgetsPendingUpdateOnceInstalled() {
        for currentBuild in ["8", "9"] {
            let defaults = makeDefaults()
            AppUpdates(defaults: defaults, currentBuild: "7").noteUpdateFound(version: "0.5.1", build: "8")

            let updated = AppUpdates(defaults: defaults, currentBuild: currentBuild)
            XCTAssertNil(updated.pendingVersion, "今のビルド \(currentBuild)")
            XCTAssertNil(defaults.string(forKey: AppUpdates.Key.pendingVersion))
            XCTAssertNil(defaults.string(forKey: AppUpdates.Key.pendingBuild))
        }
    }

    /// 片付いた版（飛ばした版など）は、起動し直しても戻さない
    func testClearedUpdateStaysCleared() {
        let defaults = makeDefaults()
        let updates = AppUpdates(defaults: defaults, currentBuild: "7")
        updates.noteUpdateFound(version: "0.5.1", build: "8")
        updates.clearPendingUpdate()

        XCTAssertNil(AppUpdates(defaults: defaults, currentBuild: "7").pendingVersion)
    }

    /// ビルド番号は数として比べる（10 は 9 より新しい）
    func testComparesBuildNumbersAsNumbers() {
        XCTAssertTrue(AppUpdates.isBuild("10", newerThan: "9"))
        XCTAssertFalse(AppUpdates.isBuild("9", newerThan: "10"))
        XCTAssertFalse(AppUpdates.isBuild("8", newerThan: "8"))
    }
}
