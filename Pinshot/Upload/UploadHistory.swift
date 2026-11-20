import AppKit

/// 上げたものの履歴（共有リンクの一覧と、小さな縮小画像）。
/// 上げたもの自体は保存先にあるので、ここには置かない。期間や数で自動では消さない（消すと、リンクを探せなくなるため）
@MainActor
final class UploadHistory: ObservableObject {
    static let shared = UploadHistory()

    /// 履歴（新しい順）
    @Published private(set) var entries: [UploadHistoryEntry] = []

    let folder = AppFolders.uploads
    private var indexURL: URL { folder.appendingPathComponent("uploads.json") }
    /// ファイルの読み書きは、画面を止めないよう、この順番待ちの列で行う
    private let io = DispatchQueue(label: "Pinshot.UploadHistory", qos: .utility)

    private init() {
        entries = loadIndex()
    }

    // MARK: - 足す

    /// 上げたものを足す（thumbnail があれば、縮小画像も残す）
    @discardableResult
    func add(remote: RemoteFile, link: SharedLink, kind: ExportKind, fileName: String, thumbnail: CGImage?) -> UploadHistoryEntry {
        let entry = UploadHistoryEntry(id: UUID(), date: Date(), remote: remote, link: link, kind: kind, fileName: fileName)
        entries = UploadHistoryRules.adding(entry, to: entries)
        if let thumbnail {
            writeThumbnail(thumbnail, to: folder.appendingPathComponent(entry.thumbnailFileName))
        }
        saveIndex()
        return entry
    }

    // MARK: - 使う

    /// 一覧に出す縮小画像（なければ nil。書き終える前も nil）
    func thumbnail(for entry: UploadHistoryEntry) -> NSImage? {
        NSImage(contentsOf: folder.appendingPathComponent(entry.thumbnailFileName))
    }

    /// 共有リンクを format の形でコピーする（2 件以上は、1 行に 1 つずつ並べる）
    func copyLinks(of entries: [UploadHistoryEntry], format: ShareLinkFormat) {
        let text = entries.map { UploadRules.clipboardText(for: $0.link, format: format) }.joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func openInBrowser(_ entry: UploadHistoryEntry) {
        NSWorkspace.shared.open(entry.link.pageURL)
    }

    // MARK: - 消す

    /// 履歴から外す。fromDestination なら、保存先からも消す（消せなかったものは、履歴に残して投げる）
    func remove(_ targets: [UploadHistoryEntry], fromDestination: Bool) async throws {
        var removed: [UploadHistoryEntry] = []
        var failure: Error?
        for entry in targets {
            // 消せない保存先のものは、一覧から外すだけにする
            if fromDestination,
               let destination = UploadDestinations.destination(for: entry.destination),
               destination.capabilities.canDelete {
                do {
                    try await destination.delete(entry.remote)
                } catch UploadError.server(_, let status, _) where status == 404 {
                    // 保存先で、もう消されていた
                } catch {
                    failure = error
                    continue
                }
            }
            removed.append(entry)
        }
        let ids = Set(removed.map(\.id))
        entries.removeAll { ids.contains($0.id) }
        deleteThumbnails(of: removed)
        saveIndex()
        if let failure { throw failure }
    }

    // MARK: - ファイル

    private func writeThumbnail(_ image: CGImage, to url: URL) {
        let folder = folder
        io.async { [weak self] in
            let pixelSize = CGSize(width: image.width, height: image.height)
            let size = CaptureHistoryRules.thumbnailSize(for: pixelSize)
            guard let thumb = image.scaled(to: size), let png = ImageExporter.pngData(thumb, pointSize: size) else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? png.write(to: url, options: .atomic)
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }
    }

    private func deleteThumbnails(of removed: [UploadHistoryEntry]) {
        let urls = removed.map { folder.appendingPathComponent($0.thumbnailFileName) }
        guard !urls.isEmpty else { return }
        io.async {
            urls.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    /// 一覧を読む（1 件ずつ読み、読めないもの（いまはない上げる先のものなど）だけ飛ばす。
    /// そのときは元のファイルを別名で残す。StoredJSON）。この一覧は自動では消さないので、1 件のせいで全部を失わないようにする
    private func loadIndex() -> [UploadHistoryEntry] {
        StoredJSON.loadList(UploadHistoryEntry.self, from: indexURL).elements.sorted { $0.date > $1.date }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        let url = indexURL
        io.async { StoredJSON.write(data, to: url) }
    }
}
