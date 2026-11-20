import AppKit

/// アップロードの入口（どの保存先でも同じに動かす）。
/// 選んでいる保存先に上げ → 共有リンクを作り → 設定の形でクリップボードに入れ → 履歴に残し → 知らせる
@MainActor
final class UploadCenter {
    static let shared = UploadCenter()

    /// 上げている途中の数が 0 になった・0 でなくなったとき（メニューバーのアイコンを変える）
    var onActivityChange: ((Bool) -> Void)?
    /// 上げている途中の数
    private(set) var activeCount = 0 {
        didSet {
            if (activeCount > 0) != (oldValue > 0) { onActivityChange?(activeCount > 0) }
        }
    }

    /// 画像を上げて、共有リンクをコピーする（PNG にする重い処理は裏で行う）。
    /// automatic: 撮ったときに自動で上げる（つないでいなければ、確かめる画面を出さずにやめる）。
    /// notify には、進み具合と結果の知らせを渡す（浮かせた画像の上のお知らせなど）
    func shareImage(_ image: CGImage, pointSize: CGSize, automatic: Bool = false, notify: @escaping (UploadStatus) -> Void) {
        if automatic, !isReadyForAutomaticUpload {
            notify(.finished("自動で上げられませんでした（上げる先につながっていません）"))
            return
        }
        Task {
            notify(.working("上げる準備をしています…", progress: nil))
            let data = await Task.detached(priority: .userInitiated) {
                ImageExporter.pngData(image, pointSize: pointSize)
            }.value
            guard let data else {
                notify(.finished("画像を用意できませんでした"))
                return
            }
            let item = UploadItem(payload: .data(data), fileName: UploadRules.fileName(kind: .image, date: Date()), kind: .image)
            await run(item, thumbnail: image, automatic: automatic, notify: notify)
        }
    }

    /// 自動で上げられる状態か（上げる先を選び、つないでいる）
    private var isReadyForAutomaticUpload: Bool {
        UploadDestinations.current?.isSignedIn == true
    }

    // MARK: - 上げる

    private func run(_ item: UploadItem, thumbnail: CGImage?, automatic: Bool, notify: @escaping (UploadStatus) -> Void) async {
        guard let destination = UploadDestinations.current else {
            notify(.finished("上げる先が選ばれていません"))
            openSettings(
                "共有リンクの上げる先が選ばれていません",
                detail: "設定の「共有」で、上げる先（Gyazo など）を選んでつないでください。"
            )
            return
        }
        let label = destination.id.label
        if item.kind == .movie, !destination.capabilities.uploadsMovies {
            notify(.finished("上げられませんでした"))
            AppAlert.inform(UploadError.unsupportedKind(destination.id, item.kind).localizedDescription)
            return
        }
        guard destination.capabilities.accepts(item.kind, bytes: item.payload.byteCount) else {
            notify(.finished("上げられませんでした"))
            AppAlert.inform(UploadError.tooLarge(destination.id).localizedDescription)
            return
        }
        if !destination.isSignedIn {
            guard !automatic, await signIn(destination) else {
                notify(.finished("\(label) につないでから、もう一度上げてください"))
                return
            }
        }

        let working = "\(label) に上げています…"
        notify(.working(working, progress: 0))
        activeCount += 1
        defer { activeCount -= 1 }
        // 送った割合を、1% ずつ知らせる（細かく知らせすぎないように）
        let reporter = ProgressReporter { value in notify(.working(working, progress: value)) }
        do {
            let file = try await destination.upload(item) { value in
                Task { @MainActor in reporter.report(value) }
            }
            notify(.working("リンクを作っています…", progress: nil))
            let link = try await destination.shareLink(for: file)
            let text = UploadRules.clipboardText(for: link, format: AppSettings.shared.shareLinkFormat)
            copy(text)
            UploadHistory.shared.add(remote: file, link: link, kind: item.kind, fileName: item.fileName, thumbnail: thumbnail)
            notify(.finished("リンクをコピーしました"))
            UploadNotifier.shared.notify(title: "\(label) のリンクをコピーしました", body: text, link: link.pageURL)
        } catch UploadError.cancelled {
            notify(.finished("やめました"))
        } catch UploadError.notSignedIn {
            notify(.finished("\(label) につなぎ直してください"))
            openSettings(
                "\(label) につなぎ直してください",
                detail: "許可が切れたか、取り消されました。つなぎ直してから、もう一度上げてください。"
            )
        } catch {
            notify(.finished("上げられませんでした"))
            if automatic {
                // 撮るたびに画面を止めないよう、自動のときは通知で知らせる
                UploadNotifier.shared.notify(title: "\(label) に上げられませんでした", body: error.localizedDescription)
            } else {
                AppAlert.inform("\(label) に上げられませんでした", detail: error.localizedDescription)
            }
        }
    }

    /// ログインしていなければ、ログインしてもらう（できたら true）
    private func signIn(_ destination: UploadDestination) async -> Bool {
        switch destination.signInStyle {
        case .oauth:
            do {
                try await destination.signIn()
                return true
            } catch UploadError.cancelled {
                return false
            } catch {
                AppAlert.inform("\(destination.id.label) にログインできませんでした", detail: error.localizedDescription)
                return false
            }
        case .pastedToken:
            // つなぐまでの手順を、案内の窓で進めてもらう（つないだら、もう一度上げてもらう）
            GyazoSetupWindowController.shared.show()
            return false
        }
    }

    private func openSettings(_ message: String, detail: String) {
        AppAlert.confirm(message, detail: detail, confirmTitle: "設定を開く") {
            SettingsWindowController.shared.show(tab: SettingsWindowController.shareTab)
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// アップロードの進み具合と結果の知らせ
enum UploadStatus {
    /// 途中（知らせを出したままにする。progress は送った割合 0〜1。分からなければ nil）
    case working(String, progress: Double?)
    /// 終わった・やめた（少したつと消える）
    case finished(String)

    var text: String {
        switch self {
        case .working(let text, _), .finished(let text): text
        }
    }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    var progress: Double? {
        if case .working(_, let progress) = self { return progress }
        return nil
    }
}

/// 送った割合を、1% 進むごとに知らせる
@MainActor
private final class ProgressReporter {
    private let onReport: (Double) -> Void
    private var last = -1.0

    init(_ onReport: @escaping (Double) -> Void) {
        self.onReport = onReport
    }

    func report(_ value: Double) {
        guard value - last >= 0.01 || value >= 1 else { return }
        last = value
        onReport(value)
    }
}
