import AppKit
import Combine

/// 撮った画像の履歴。画像（PNG）と縮小画像と一覧（JSON）を、アプリ用のフォルダに置く。
/// 置き場所の決まり（AppFolders）は、浮かせた画像を終了後も戻す機能でも使う
@MainActor
final class CaptureHistory: ObservableObject {
    static let shared = CaptureHistory()

    /// 履歴（新しい順）
    @Published private(set) var entries: [CaptureHistoryEntry] = []

    let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("history.json") }
    /// ファイルの読み書きは、画面を止めないよう、この順番待ちの列で行う
    private let io = DispatchQueue(label: "Pinshot.CaptureHistory", qos: .utility)
    private var cancellables = Set<AnyCancellable>()

    var totalBytes: Int { entries.reduce(0) { $0 + $1.byteCount } }
    /// 枚数と容量（例: 「12 枚・3.4 MB」。なければ「なし」）
    var summaryText: String { CaptureHistoryRules.summaryText(count: entries.count, bytes: totalBytes) }

    private init() {
        folder = AppFolders.history
        entries = loadIndex()
        // 期間・枚数の設定を変えたら、外れた分をすぐ消す
        let settings = AppSettings.shared
        settings.$historyPeriod.combineLatest(settings.$historyLimit)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.pruneExpired() }
            .store(in: &cancellables)
        pruneExpired()
    }

    // MARK: - 足す

    /// 撮った画像を履歴に足す（設定で残さないときは何もしない）。PNG を作る重い処理は裏で行う
    func add(image: CGImage, pointSize: CGSize) {
        guard AppSettings.shared.historyEnabled else { return }
        let id = UUID()
        let date = Date()
        let folder = folder
        io.async { [weak self] in
            guard let saved = Self.writeFiles(image: image, pointSize: pointSize, id: id, date: date, folder: folder) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.entries.insert(saved, at: 0)
                self.pruneExpired()
                self.saveIndex()
            }
        }
    }

    /// 画像と縮小画像を書く（裏で呼ぶ）。書けなければ nil
    nonisolated private static func writeFiles(
        image: CGImage,
        pointSize: CGSize,
        id: UUID,
        date: Date,
        folder: URL
    ) -> CaptureHistoryEntry? {
        let pixelSize = CGSize(width: image.width, height: image.height)
        var entry = CaptureHistoryEntry(id: id, date: date, pointSize: pointSize, pixelSize: pixelSize, byteCount: 0)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let png = ImageExporter.pngData(image, pointSize: pointSize) else { return nil }
            try png.write(to: folder.appendingPathComponent(entry.imageFileName), options: .atomic)
            let thumbSize = CaptureHistoryRules.thumbnailSize(for: pixelSize)
            var thumbBytes = 0
            if let thumb = scaled(image, to: thumbSize), let thumbPNG = ImageExporter.pngData(thumb, pointSize: thumbSize) {
                try thumbPNG.write(to: folder.appendingPathComponent(entry.thumbnailFileName), options: .atomic)
                thumbBytes = thumbPNG.count
            }
            entry.byteCount = png.count + thumbBytes
            return entry
        } catch {
            NSLog("Pinshot: 履歴に保存できませんでした: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated private static func scaled(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard let ctx = CGContext.makeRGBA(width: Int(size.width), height: Int(size.height), space: image.rgbColorSpace) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return ctx.makeImage()
    }

    // MARK: - 読む

    func imageURL(for entry: CaptureHistoryEntry) -> URL {
        folder.appendingPathComponent(entry.imageFileName)
    }

    func thumbnailURL(for entry: CaptureHistoryEntry) -> URL {
        folder.appendingPathComponent(entry.thumbnailFileName)
    }

    /// 縮小画像を読む（縮小画像がなければ、元の画像）
    func thumbnailImage(for entry: CaptureHistoryEntry) -> NSImage? {
        NSImage(contentsOf: thumbnailURL(for: entry)) ?? NSImage(contentsOf: imageURL(for: entry))
    }

    /// メニューに出す小さな縮小画像（高さ 24pt）
    func menuThumbnail(for entry: CaptureHistoryEntry) -> NSImage? {
        guard let image = thumbnailImage(for: entry) else { return nil }
        let height: CGFloat = 24
        let width = min(48, max(12, height * entry.pointSize.width / max(entry.pointSize.height, 1)))
        image.size = NSSize(width: width, height: height)
        return image
    }

    /// 画像を読む（浮かせる・コピーするとき）
    func loadImage(for entry: CaptureHistoryEntry) -> CGImage? {
        CGImage.load(contentsOf: imageURL(for: entry))
    }

    // MARK: - 浮かせる・コピーする（一覧・メニューバーから）

    /// マウスのある画面の真ん中に浮かせる（2 枚以上は、少しずつずらして重ねる）。浮かせた枚数を返す
    @discardableResult
    func pin(_ targets: [CaptureHistoryEntry]) -> Int {
        var pinned = 0
        for entry in targets {
            guard let image = loadImage(for: entry) else { continue }
            PinManager.shared.pinAtMouseScreen(image: image, imageSize: entry.pointSize, offset: CGFloat(pinned) * 24)
            pinned += 1
        }
        if pinned == 0 { NSSound.beep() }
        return pinned
    }

    /// クリップボードにコピーする。読めなければ音で知らせて false
    @discardableResult
    func copy(_ entry: CaptureHistoryEntry) -> Bool {
        guard let image = loadImage(for: entry) else {
            NSSound.beep()
            return false
        }
        ImageExporter.writeToPasteboard(image, pointSize: entry.pointSize)
        return true
    }

    // MARK: - 消す

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let removed = entries.filter { ids.contains($0.id) }
        entries.removeAll { ids.contains($0.id) }
        deleteFiles(of: removed)
        saveIndex()
    }

    func removeAll() {
        let removed = entries
        entries.removeAll()
        deleteFiles(of: removed)
        saveIndex()
    }

    /// 期間を過ぎたもの・枚数を超えた古いものを消す
    func pruneExpired() {
        let settings = AppSettings.shared
        let expired = CaptureHistoryRules.expired(entries, now: Date(), period: settings.historyPeriod, limit: settings.historyLimit)
        guard !expired.isEmpty else { return }
        remove(ids: Set(expired.map(\.id)))
    }

    private func deleteFiles(of removed: [CaptureHistoryEntry]) {
        let urls = removed.flatMap { [imageURL(for: $0), thumbnailURL(for: $0)] }
        io.async {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - 一覧のファイル

    private func loadIndex() -> [CaptureHistoryEntry] {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([CaptureHistoryEntry].self, from: data) else { return [] }
        // 画像のファイルがなくなっているものは除く
        return saved
            .filter { FileManager.default.fileExists(atPath: imageURL(for: $0).path) }
            .sorted { $0.date > $1.date }
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
