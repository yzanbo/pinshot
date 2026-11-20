import AppKit
import Combine

/// 読み取った文字の履歴。一覧（JSON）と、読み取った範囲の画像（PNG）を、撮った画像の履歴と同じフォルダに置く。
/// 残す期間と数は、文字の履歴の設定（撮った画像の履歴とは別）に合わせる
@MainActor
final class TextHistory: ObservableObject {
    static let shared = TextHistory()

    /// 履歴（新しい順）
    @Published private(set) var entries: [RecognizedTextEntry] = []

    let folder = AppFolders.history
    private var indexURL: URL { folder.appendingPathComponent("texts.json") }
    /// ファイルの読み書きは、画面を止めないよう、この順番待ちの列で行う
    private let io = DispatchQueue(label: "Pinshot.TextHistory", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    /// 残す画像の長い辺の上限（ピクセル。読み取った範囲が大きい画像でも、容量を抑える）
    private static let maxImageSide: CGFloat = 1600

    /// 件数（例: 「12 件」。なければ「なし」）
    var summaryText: String { TextHistoryRules.summaryText(count: entries.count) }

    private init() {
        entries = loadIndex()
        // 期間・数の設定を変えたら、外れた分をすぐ消す
        let settings = AppSettings.shared
        settings.$textHistoryPeriod.combineLatest(settings.$textHistoryLimit)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.pruneExpired() }
            .store(in: &cancellables)
        pruneExpired()
    }

    // MARK: - 足す・直す

    /// 読み取った文字を履歴に足す（設定で残さないときは何もしない）。同じ文字は先頭に移す。
    /// image は読み取った範囲の画像（pointSize はその大きさ）。どの画像の文字かを一覧で見せるために残す
    func add(_ text: String, image: CGImage? = nil, pointSize: CGSize? = nil) {
        guard AppSettings.shared.textHistoryEnabled, !text.isEmpty else { return }
        let id = UUID()
        var entry = RecognizedTextEntry(id: id, date: Date(), text: text)
        if let image {
            let fileName = RecognizedTextEntry.imageFileName(for: id)
            let size = pointSize ?? CGSize(width: image.width, height: image.height)
            entry.imageFileName = fileName
            entry.pointSize = size
            writeImage(image, pointSize: size, to: imageURL(fileName: fileName))
        }
        let replaced = entries.filter { $0.text == text }
        entries = TextHistoryRules.adding(entry, to: entries)
        deleteImages(of: replaced)
        pruneExpired()
        saveIndex()
    }

    /// 同じ文字の履歴（読み取ったときは同じ文字を 1 件にまとめているので、ふつうは 1 件）
    func entry(withText text: String) -> RecognizedTextEntry? {
        entries.first { $0.text == text }
    }

    /// 履歴の文字を直す（一覧・読み取ったあとの吹き出しで直したとき）。空にはしない
    func replaceText(of id: UUID, with text: String) {
        guard !text.isEmpty, let index = entries.firstIndex(where: { $0.id == id }), entries[index].text != text else { return }
        entries[index].text = text
        saveIndex()
    }

    /// クリップボードにコピーする
    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - 読み取った範囲の画像

    func imageURL(for entry: RecognizedTextEntry) -> URL? {
        entry.imageFileName.map(imageURL(fileName:))
    }

    private func imageURL(fileName: String) -> URL {
        folder.appendingPathComponent(fileName)
    }

    /// 一覧に出す画像（なければ nil。書き終える前も nil）
    func image(for entry: RecognizedTextEntry) -> NSImage? {
        imageURL(for: entry).flatMap(NSImage.init(contentsOf:))
    }

    /// 読み取った範囲の画像を、マウスのある画面の真ん中に浮かせる。読めなければ音で知らせる
    func pinImage(of entry: RecognizedTextEntry) {
        guard let (image, size) = loadImage(of: entry) else { return NSSound.beep() }
        PinManager.shared.pinAtMouseScreen(image: image, imageSize: size)
    }

    /// 読み取った範囲の画像を、クリップボードにコピーする。読めなければ音で知らせて false
    @discardableResult
    func copyImage(of entry: RecognizedTextEntry) -> Bool {
        guard let (image, size) = loadImage(of: entry) else {
            NSSound.beep()
            return false
        }
        ImageExporter.writeToPasteboard(image, pointSize: size)
        return true
    }

    /// 読み取った範囲の画像と、その大きさ（ポイント）
    private func loadImage(of entry: RecognizedTextEntry) -> (CGImage, CGSize)? {
        guard let url = imageURL(for: entry), let image = CGImage.load(contentsOf: url) else { return nil }
        return (image, entry.pointSize ?? CGSize(width: image.width, height: image.height))
    }

    /// 画像を書く（大きいときは縮める。重いので裏で行い、書き終えたら一覧を描き直す）
    private func writeImage(_ image: CGImage, pointSize: CGSize, to url: URL) {
        let folder = folder
        io.async { [weak self] in
            let pixelSize = CGSize(width: image.width, height: image.height)
            let size = CaptureHistoryRules.thumbnailSize(for: pixelSize, maxSide: Self.maxImageSide)
            let stored = size == pixelSize ? image : (image.scaled(to: size) ?? image)
            guard let png = ImageExporter.pngData(stored, pointSize: pointSize) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: url, options: .atomic)
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    // MARK: - 消す

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removed = entries.filter { ids.contains($0.id) }
        entries.removeAll { ids.contains($0.id) }
        deleteImages(of: removed)
        saveIndex()
    }

    func removeAll() {
        remove(ids: Set(entries.map(\.id)))
    }

    /// 期間を過ぎたもの・数を超えた古いものを消す
    func pruneExpired() {
        let settings = AppSettings.shared
        let expired = CaptureHistoryRules.expired(entries, now: Date(), period: settings.textHistoryPeriod, limit: settings.textHistoryLimit)
        guard !expired.isEmpty else { return }
        remove(ids: Set(expired.map(\.id)))
    }

    private func deleteImages(of removed: [RecognizedTextEntry]) {
        let urls = removed.compactMap(imageURL(for:))
        guard !urls.isEmpty else { return }
        io.async {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - 一覧のファイル

    private func loadIndex() -> [RecognizedTextEntry] {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([RecognizedTextEntry].self, from: data) else { return [] }
        return saved.sorted { $0.date > $1.date }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let url = indexURL
        let folder = folder
        io.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

extension TextRecognizer {
    /// 読み取った文字をクリップボードに入れ、読み取った文字の履歴に残す（文字がなければ、どちらもしない）。
    /// pointSize は image の大きさ（ポイント）。履歴に画像を残すときに使う
    @MainActor
    static func copyText(in image: CGImage, pointSize: CGSize? = nil) async -> TextRecognitionResult {
        let result = await recognize(image)
        guard !result.text.isEmpty else { return result }
        TextHistory.shared.copy(result.text)
        TextHistory.shared.add(result.text, image: image, pointSize: pointSize)
        return result
    }
}
