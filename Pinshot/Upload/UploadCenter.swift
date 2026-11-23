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
            let item = UploadItem(data: data, fileName: UploadRules.fileName(kind: .image, date: Date()), kind: .image)
            await run(item, thumbnail: image, automatic: automatic, notify: notify)
        }
    }

    /// 自動で上げられる状態か（上げる先を選び、つないでいる）
    private var isReadyForAutomaticUpload: Bool {
        UploadDestinations.current?.isSignedIn == true
    }

    // MARK: - 録画を GIF にして上げる

    /// 録画を GIF にして上げ、共有リンクをコピーする（浮かせた録画の窓から）。
    /// 上げる先の大きさの上限は分からないので、Pinshot の上限（UploadRules.gifMaxBytes）を超えたら、
    /// 小さい作り方（RecordingRules.gifUploadSteps）で作り直す。上げる先に「大きすぎる」と断られたときも、小さくして上げ直す。
    /// いちばん小さくしても上げられなければ、そう知らせる。notify には、進み具合と結果を渡す（最後はいつも finished）
    func shareGIF(fromMovieAt movieURL: URL, notify: @escaping (UploadStatus) -> Void) {
        Task {
            // GIF を作るのは時間がかかるので、先に上げる先を選んでいて、つないでいるかを確かめる
            guard let destination = await readyDestination(automatic: false, notify: notify) else { return }
            let label = destination.id.label
            let thumbnail = await GIFExporter.firstFrame(of: movieURL)
            let steps = RecordingRules.gifUploadSteps
            var lastBytes = 0
            for (index, settings) in steps.enumerated() {
                let isLast = index == steps.count - 1
                let making = index == 0 ? "GIF を作っています…" : "GIF を小さくして作り直しています…"
                notify(.working(making, progress: 0))
                let data: Data
                do {
                    data = try await Self.makeGIF(from: movieURL, settings: settings) { value in
                        notify(.working(making, progress: value))
                    }
                } catch {
                    notify(.finished("GIF を作れませんでした"))
                    AppAlert.inform("GIF を作れませんでした", detail: error.localizedDescription)
                    return
                }
                lastBytes = data.count
                // Pinshot の上限を超えたら、小さい作り方で作り直す
                guard UploadRules.fitsGIFUpload(bytes: data.count) else { continue }
                let item = UploadItem(data: data, fileName: UploadRules.fileName(kind: .gif, date: Date()), kind: .gif)
                // 上げる先に「大きすぎる」と断られたら、小さい作り方があれば作り直して上げ直す
                if await run(item, thumbnail: thumbnail, automatic: false, retriesIfTooLarge: !isLast, notify: notify) == .tooLarge {
                    continue
                }
                return
            }
            // いちばん小さい作り方でも、Pinshot の上限を超えた・上げる先に断られた
            notify(.finished("GIF が大きすぎて、上げられませんでした"))
            informGIFTooLarge(label: label, bytes: lastBytes)
        }
    }

    /// 録画から、settings の作り方で GIF を作り、中身を返す（作るのに使った一時ファイルは消す）
    private static func makeGIF(
        from movieURL: URL,
        settings: GIFSettings,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> Data {
        let temporary = try await GIFExporter.exportToTemporaryFile(videoAt: movieURL, settings: settings, progress: progress)
        defer { try? FileManager.default.removeItem(at: temporary) }
        return try Data(contentsOf: temporary)
    }

    /// いちばん小さくしても上げられなかったことを、大きさ・上限と、どうすればよいかと一緒に知らせる
    private func informGIFTooLarge(label: String, bytes: Int) {
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        let limit = ByteCountFormatter.string(fromByteCount: Int64(UploadRules.gifMaxBytes), countStyle: .file)
        AppAlert.inform(
            "GIF が大きすぎて、\(label) に上げられませんでした",
            detail: "いちばん小さくして作り直しても \(size) ありました（上げる GIF は \(limit) まで）。"
                + "録画を短くするか、範囲を小さくして録り直してください。「GIF で保存」「MP4 で保存」したファイルを、ほかの方法で送ることもできます。"
        )
    }

    // MARK: - 上げる

    /// 上げたときの終わり方（上げる先に「大きすぎる」と断られて、呼ぶ側が作り直すときだけ tooLarge）
    private enum RunResult {
        case done
        case tooLarge
    }

    /// 上げる先を選んでいて、つないでいれば、その上げる先を返す。
    /// 選んでいなければ設定を開くよう勧め、つないでいなければつなぐ案内を出して（自動のときは出さずに）nil を返す
    private func readyDestination(automatic: Bool, notify: @escaping (UploadStatus) -> Void) async -> UploadDestination? {
        guard let destination = UploadDestinations.current else {
            notify(.finished("上げる先が選ばれていません"))
            openSettings(
                "共有リンクの上げる先が選ばれていません",
                detail: "設定の「共有」で、上げる先（Gyazo など）を選んでつないでください。"
            )
            return nil
        }
        if !destination.isSignedIn {
            guard !automatic, await signIn(destination) else {
                notify(.finished("\(destination.id.label) につないでから、もう一度上げてください"))
                return nil
            }
        }
        return destination
    }

    /// item を上げて、共有リンクをコピーする。retriesIfTooLarge なら、上げる先に「大きすぎる」と断られたときに
    /// 知らせずに tooLarge を返す（呼ぶ側が小さくして上げ直す）
    @discardableResult
    private func run(
        _ item: UploadItem,
        thumbnail: CGImage?,
        automatic: Bool,
        retriesIfTooLarge: Bool = false,
        notify: @escaping (UploadStatus) -> Void
    ) async -> RunResult {
        guard let destination = await readyDestination(automatic: automatic, notify: notify) else { return .done }
        let label = destination.id.label
        if item.kind == .movie, !destination.capabilities.uploadsMovies {
            notify(.finished("上げられませんでした"))
            AppAlert.inform(UploadError.unsupportedKind(destination.id, item.kind).localizedDescription)
            return .done
        }
        guard destination.capabilities.accepts(item.kind, bytes: item.byteCount) else {
            if retriesIfTooLarge { return .tooLarge }
            notify(.finished("上げられませんでした"))
            AppAlert.inform(UploadError.tooLarge(destination.id).localizedDescription)
            return .done
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
        } catch UploadError.tooLarge where retriesIfTooLarge {
            // 呼ぶ側が小さくして上げ直す
            return .tooLarge
        } catch UploadError.cancelled {
            notify(.finished("やめました"))
        } catch UploadError.notSignedIn {
            notify(.finished("\(label) につなぎ直してください"))
            let title = "\(label) につなぎ直してください"
            let detail = "許可が切れたか、取り消されました。つなぎ直してから、もう一度上げてください。"
            if automatic {
                // 撮るたびに画面を止めないよう、自動のときは通知で知らせる（ほかの失敗と同じ）
                UploadNotifier.shared.notify(title: title, body: detail)
            } else {
                openSettings(title, detail: detail)
            }
        } catch {
            notify(.finished("上げられませんでした"))
            if automatic {
                // 撮るたびに画面を止めないよう、自動のときは通知で知らせる
                UploadNotifier.shared.notify(title: "\(label) に上げられませんでした", body: error.localizedDescription)
            } else {
                AppAlert.inform("\(label) に上げられませんでした", detail: error.localizedDescription)
            }
        }
        return .done
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
