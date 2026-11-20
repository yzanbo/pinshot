import Foundation

/// アプリが残す一覧と状態の JSON（撮った画像・読み取った文字・上げたものの履歴と、浮かせていた画像）を読み書きする決まり。
/// どれも、読めなかったときに次の保存で上書きして中身を失わないよう、同じ決まりにそろえる（テストで確かめる）。
/// - 配列は 1 件ずつ読み、読めないもの（壊れた・新しい版で足した種類など）だけを飛ばす（1 件のせいで全部を失わない）
/// - 読めないものがあったときは、元のファイルを同じフォルダに別名（〜.unreadable-日時.json）で写して残す
enum StoredJSON {
    /// 読んだ配列と、読めずに飛ばした数
    struct Loaded<Element> {
        var elements: [Element]
        var skipped: Int
    }

    /// url の JSON の配列を 1 件ずつ読む。ファイルがなければ空。
    /// 配列として読めない・読めない件があったときは、元のファイルを別名で残す（keepUnreadable）
    static func loadList<Element: Decodable>(_ type: Element.Type, from url: URL, now: Date = Date()) -> Loaded<Element> {
        guard let data = try? Data(contentsOf: url) else { return Loaded(elements: [], skipped: 0) }
        guard let loaded = decodeList(type, from: data) else {
            keepUnreadable(url, now: now)
            return Loaded(elements: [], skipped: 0)
        }
        if loaded.skipped > 0 { keepUnreadable(url, now: now) }
        return loaded
    }

    /// data を配列として 1 件ずつ読む（配列として読めなければ nil）
    static func decodeList<Element: Decodable>(_ type: Element.Type, from data: Data) -> Loaded<Element>? {
        guard let items = try? JSONDecoder().decode([Lossy<Element>].self, from: data) else { return nil }
        let elements = items.compactMap(\.value)
        return Loaded(elements: elements, skipped: items.count - elements.count)
    }

    /// 読めなかったファイルを、同じフォルダに別名（例: history.unreadable-20261121-031500.json）で写して残す。
    /// 同じ中身をもう残していれば、増やさない（読めないまま起動し直すたびに増えないように）。残した場所を返す
    @discardableResult
    static func keepUnreadable(_ url: URL, now: Date) -> URL? {
        let fileManager = FileManager.default
        guard let data = try? Data(contentsOf: url) else { return nil }
        let folder = url.deletingLastPathComponent()
        let prefix = url.deletingPathExtension().lastPathComponent + ".unreadable-"
        let existing = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        if let same = existing.first(where: { $0.lastPathComponent.hasPrefix(prefix) && (try? Data(contentsOf: $0)) == data }) {
            return same
        }
        let backup = backupURL(for: url, date: now)
        guard (try? fileManager.copyItem(at: url, to: backup)) != nil else { return nil }
        NSLog("Pinshot: 読めないところがあった \(url.lastPathComponent) を \(backup.lastPathComponent) に残しました")
        return backup
    }

    /// 読めなかったファイルを残す場所（例: history.json → history.unreadable-20261121-031500.json）
    static func backupURL(for url: URL, date: Date) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        return url.deletingLastPathComponent().appendingPathComponent("\(name).unreadable-\(stamp(date)).\(ext)")
    }

    /// 残すときの名前に付ける日時（例: 20261121-031500）
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// data を url に書く（フォルダがなければ作る。途中で止まっても壊れないよう、書き終えてから置き換える）。
    /// 画面を止めないよう、裏の列から呼ぶ
    static func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// 配列の 1 件を読む（読めなければ value が nil。配列の中の 1 件のせいで、全部を読めなくしないため）
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
