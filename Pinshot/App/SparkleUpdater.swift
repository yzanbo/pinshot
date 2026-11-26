import AppKit
import os
import Sparkle

/// Sparkle を使った更新（新しい版を確かめる・落とす・入れ替える）
///
/// 更新の画面（新しい版の知らせ・リリースノート・進み具合）は、Sparkle の標準のものを使う。
/// ただし、メニューや設定から確かめたときの「アップデートを確認中…」の小窓は、少なくとも 0.5 秒は出しておく
/// （問い合わせはすぐ終わるので、そのままだと小窓が一瞬で閉じ、ちらついて見えるため。`PacedUserDriver`）。
/// Pinshot はメニューバーに常駐するアプリなので、自動で見つけた新しい版は画面に割り込ませず、
/// メニューバーのアイコンの印とメニューで知らせる（Sparkle の「控えめな知らせ」の作法）。
/// 印は、入れるか利用者がその版を飛ばすまで出しておく（更新の画面を開いた・閉じただけでは消さない。`AppUpdates`）。
///
/// Sparkle を読み込むのはこのファイルだけ。メニューと設定は `AppUpdates` を通して使う
/// （make readme-images は、Sparkle なしでアプリのコードをビルドするため、このファイルを除く）。
///
/// SPUStandardUserDriverDelegate は、Sparkle の側で main actor の印が付いていないが、標準の画面はメインスレッドからだけ呼ぶので、
/// @preconcurrency で受ける（ほかのスレッドから呼ばれたら、その場で止まって分かる）。
@MainActor
final class SparkleUpdater: NSObject, AppUpdateService, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    /// 更新の画面を出している間、Dock にアイコンを出しておく印
    private static let dockHold = "update"
    private static let logger = Logger(pinshot: "update")

    private let updates: AppUpdates
    private var updater: SPUUpdater?
    /// Sparkle の標準の画面を包んだもの（SPUUpdater は弱く持つので、ここで持つ）
    private var userDriver: PacedUserDriver?
    private var canCheckObservation: NSKeyValueObservation?

    /// 更新の仕組みを始める
    ///
    /// 更新ファイルの署名を確かめる公開鍵（Info.plist の SUPublicEDKey）が入っていないビルドでは始めず、nil を返す
    /// （Sparkle に始めさせると、設定の不備の警告が出るため）。
    static func start(updates: AppUpdates) -> SparkleUpdater? {
        guard hasPublicKey else {
            logger.info("Updates are disabled: SUPublicEDKey is empty in this build")
            return nil
        }
        let updater = SparkleUpdater(updates: updates)
        guard updater.startUpdater() else { return nil }
        return updater
    }

    private static var hasPublicKey: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        return key?.isEmpty == false
    }

    private init(updates: AppUpdates) {
        self.updates = updates
        super.init()
    }

    private func startUpdater() -> Bool {
        let userDriver = PacedUserDriver(standard: SPUStandardUserDriver(hostBundle: .main, delegate: self))
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)
        // 始めるのは自分で行う（失敗したときに、英語の警告の画面を出さないように）
        do {
            try updater.start()
        } catch {
            Self.logger.error("Could not start the updater: \(error.localizedDescription, privacy: .public)")
            return false
        }
        self.updater = updater
        self.userDriver = userDriver
        // 確かめられるかは、裏でダウンロードしている間などに変わるので、変わるたびに画面の側へ伝える
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.updates.refresh() }
        }
        updates.attach(self)
        return true
    }

    // MARK: - AppUpdateService

    var checksAutomatically: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    var canCheck: Bool {
        updater?.canCheckForUpdates ?? false
    }

    var lastCheckDate: Date? {
        updater?.lastUpdateCheckDate
    }

    func checkForUpdates() {
        // 確かめられないとき（裏でダウンロードしている途中など）は何もしない（Dock に出したままにならないように）
        guard let updater, updater.canCheckForUpdates else { return }
        // Pinshot はふだん前面のアプリにならないので、Dock に出して前面にしてから確かめる（更新の画面が後ろに隠れないように）。
        // Dock からは、確かめ終えたとき（didFinishUpdateCycleFor）に消す
        DockIcon.hold(Self.dockHold)
        NSApp.activate()
        updater.checkForUpdates()
    }

    // MARK: - SPUUpdaterDelegate

    /// 確かめ終えた（新しい版がなかった・あとにした・失敗したときも）。Dock から消して、最後に確かめた日時を画面に反映する
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        DockIcon.release(Self.dockHold)
        updates.refresh()
    }

    /// 確かめたら、新しい版がなかった（知らせていた版を取り下げた・利用者が飛ばした版だけだったときも）。印を消す
    /// （通信の失敗では呼ばれないので、つながらないときは印を残す）
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updates.clearPendingUpdate()
    }

    /// 更新の画面で選んだ。「このバージョンはスキップ」のときだけ印を消す
    /// （「あとで通知」・閉じたときは、まだ入れていないので残す。入れたときは、新しい版で開き直したときに AppUpdates が消す）
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        Self.logger.notice("User choice for version \(updateItem.displayVersionString, privacy: .public): \(Self.describe(choice), privacy: .public)")
        if choice == .skip {
            updates.clearPendingUpdate()
        }
    }

    private static func describe(_ choice: SPUUserUpdateChoice) -> String {
        switch choice {
        case .skip: return "skip"
        case .install: return "install"
        case .dismiss: return "dismiss"
        @unknown default: return "unknown"
        }
    }

    // MARK: - SPUStandardUserDriverDelegate（控えめな知らせ）

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// 自動で見つけた新しい版は、Sparkle に画面を出させず、メニューバーで知らせる（起動してすぐのときも割り込まない）
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // どう知らせたかを記録に残す（自動で見つけたときに、画面を割り込ませていないことを、あとから確かめられるように）
        let notice = handleShowingUpdate ? "showing the update window" : "showing the menu bar badge"
        Self.logger.notice("Found version \(update.displayVersionString, privacy: .public): \(notice, privacy: .public)")
        if handleShowingUpdate {
            // Sparkle が更新の画面を出す（メニューから確かめたとき）。出している間は Dock に出す
            DockIcon.hold(Self.dockHold)
        }
        // どちらの見つけ方でも、入れるか飛ばすまで印を出しておく（メニューから確かめて「あとで通知」を選んだときも残すため。
        // versionString がビルド番号で、起動したときに今の版と比べる）
        updates.noteUpdateFound(version: update.displayVersionString, build: update.versionString)
    }

    /// 更新の画面を閉じた（印は消さない。Dock の後始末だけする）
    func standardUserDriverWillFinishUpdateSession() {
        DockIcon.release(Self.dockHold)
    }
}

/// Sparkle の標準の画面を包み、「アップデートを確認中…」の小窓を少なくとも minimumCheckingDuration は出しておくもの
///
/// 問い合わせはすぐ終わるので、そのままだと小窓が一瞬で閉じ、ちらついて見える。
/// 小窓を出してからの時間が足りないうちに結果（新しい版・最新版です・失敗）が届いたら、足りない分だけ待ってから標準の画面に渡す。
/// それ以外は、すべて標準の画面にそのまま任せる（公開されていない呼び出しも、そのまま標準の画面へ回す）。
@MainActor
private final class PacedUserDriver: NSObject, SPUUserDriver {
    /// 確認中の小窓を、少なくともこのあいだは出しておく
    private static let minimumCheckingDuration: Duration = .milliseconds(500)

    /// 包む標準の画面（main actor のものなので、隔離の外の responds・forwardingTarget からも読める）
    private let standard: SPUStandardUserDriver
    /// 確認中の小窓を出した時刻（出していなければ nil）
    private var checkingShownAt: ContinuousClock.Instant?

    init(standard: SPUStandardUserDriver) {
        self.standard = standard
        super.init()
    }

    // MARK: 公開されていない呼び出しを、標準の画面へ回す

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || standard.responds(to: selector)
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        standard.responds(to: selector) ? standard : super.forwardingTarget(for: selector)
    }

    // MARK: 確認中の小窓と、その結果

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        checkingShownAt = .now
        // 取りやめたら、待つ理由もなくなる（あとで自動で確かめたときの結果を、待たせないように）
        standard.showUserInitiatedUpdateCheck { [weak self] in
            self?.checkingShownAt = nil
            cancellation()
        }
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        afterMinimumChecking { [standard] in
            standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
        }
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        afterMinimumChecking { [standard] in
            standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
        }
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        afterMinimumChecking { [standard] in
            standard.showUpdaterError(error, acknowledgement: acknowledgement)
        }
    }

    /// 確認中の小窓を出してから minimumCheckingDuration たっていなければ、足りない分だけ待ってから show を呼ぶ
    /// （小窓を出していないとき＝自動で確かめたとき・時間が足りているときは、すぐに呼ぶ）
    private func afterMinimumChecking(_ show: @escaping () -> Void) {
        guard let shownAt = checkingShownAt else {
            show()
            return
        }
        checkingShownAt = nil
        let remaining = Self.minimumCheckingDuration - (ContinuousClock.now - shownAt)
        guard remaining > .zero else {
            show()
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: remaining)
            show()
        }
    }

    // MARK: そのまま標準の画面に任せるもの

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showReady(toInstallAndRelaunch: reply)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }

    func showUpdateInFocus() {
        standard.showUpdateInFocus()
    }

    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
    }
}
