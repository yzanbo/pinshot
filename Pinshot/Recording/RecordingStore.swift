import AppKit
import Combine

/// アプリの中に残す録画（~/Library/Application Support/Pinshot/Recordings）。
/// 録画を止めたら、ここに MP4 で残す（利用者が保存するときは、ここから保存先へコピーする）。
/// 残す期間・数・容量の上限は設定の「履歴」で決め、外れた古いものは自動で削除する
@MainActor
final class RecordingStore: ObservableObject {
    static let shared = RecordingStore()

    /// いま残している本数と、容量の合計（バイト）
    @Published private(set) var count = 0
    @Published private(set) var totalBytes: Int64 = 0

    let folder = AppFolders.recordings
    private var cancellables = Set<AnyCancellable>()

    /// 本数と容量（例: 「12 本・340 MB」。なければ「なし」）
    var summaryText: String { RecordingRules.summaryText(count: count, bytes: totalBytes) }

    private init() {
        // 期間・数・容量の設定を変えたら、外れた分をすぐ削除する
        let settings = AppSettings.shared
        settings.$recordingPeriod.combineLatest(settings.$recordingLimit, settings.$recordingSizeLimit)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.prune() }
            .store(in: &cancellables)
        prune()
    }

    /// 新しい録画のファイルの場所（「Pinshot 録画 日付 時刻.mp4」）
    func newURL(date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return ImageExporter.uniqueURL(in: folder, fileName: RecordingRules.fileName(for: date, extension: "mp4"))
    }

    /// 録画を足したとき（外れた古いものを削除して、本数と容量を数え直す）
    func didAdd() {
        prune()
    }

    /// 期間を過ぎたもの・数を超えた古いもの・合計が容量の上限を超えた古いものを削除する（浮かせて再生している録画は残す）
    func prune() {
        let settings = AppSettings.shared
        let expired = RecordingRules.expired(
            recordings(),
            now: Date(),
            period: settings.recordingPeriod.duration,
            keep: settings.recordingLimit.rawValue,
            maxBytes: settings.recordingSizeLimit.bytes
        )
        let playing = RecordingPlayer.openURLs
        for url in expired where !playing.contains(url) {
            try? FileManager.default.removeItem(at: url)
        }
        recount()
    }

    /// すべての録画を削除する（浮かせて再生している窓も閉じる）
    func removeAll() {
        RecordingPlayer.closeAll()
        for file in recordings() {
            try? FileManager.default.removeItem(at: file.url)
        }
        recount()
    }

    /// すべて削除する前に確かめる
    func confirmRemoveAll() {
        guard count > 0 else { return }
        AppAlert.confirm(
            "アプリの中に残している録画をすべて削除しますか？",
            detail: "\(count) 本の録画を削除します。元に戻せません（保存した MP4・GIF は削除されません）。",
            confirmTitle: "すべて削除"
        ) { [weak self] in
            self?.removeAll()
        }
    }

    // MARK: - フォルダの中身

    private func recordings() -> [RecordingFile] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys)) else { return [] }
        return urls.filter { $0.pathExtension == "mp4" }.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            return RecordingFile(url: url, date: values?.creationDate ?? .distantPast, bytes: Int64(values?.fileSize ?? 0))
        }
    }

    private func recount() {
        let files = recordings()
        count = files.count
        totalBytes = files.reduce(0) { $0 + $1.bytes }
    }
}
