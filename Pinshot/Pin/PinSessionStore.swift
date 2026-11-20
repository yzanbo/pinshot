import AppKit

/// 浮かせていた画像を、終了・再起動のあとも戻すための保存先（~/Library/Application Support/Pinshot/Pins）。
/// 画像は 1 枚ごとの PNG（一度書けば変わらない）、状態（書き込み・位置・拡大率など）は session.json に書く
@MainActor
final class PinSessionStore {
    static let shared = PinSessionStore()

    private let folder = AppFolders.pins
    private var sessionURL: URL { folder.appendingPathComponent("session.json") }
    /// ファイルの読み書きは、画面を止めないよう、この順番待ちの列で行う
    private let io = DispatchQueue(label: "Pinshot.PinSession", qos: .utility)
    /// 最後に書いた状態（変わっていなければ書かない）
    private var lastSaved: Data?

    /// 状態を書く。images は画像のファイル名ごとの画像（まだ書いていない画像だけを PNG にする）。
    /// wait: 書き終えるまで待つ（終了するとき）
    func save(_ session: SavedPinSession, images: [String: (image: CGImage, size: CGSize)], wait: Bool) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let fileManager = FileManager.default
        let missing = images.filter { !fileManager.fileExists(atPath: folder.appendingPathComponent($0.key).path) }
        guard data != lastSaved || !missing.isEmpty else {
            // 変わっていなくても、終了するときは、先に予約した書き込みが終わるまで待つ
            if wait { io.sync {} }
            return
        }
        lastSaved = data
        let folder = folder
        let sessionURL = sessionURL
        let keep = session.imageFileNames
        // 裏の列（io）で動かすので @Sendable にする（Swift の並行処理のチェックで警告にならないように）
        let work: @Sendable () -> Void = {
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, item) in missing {
                if let png = ImageExporter.pngData(item.image, pointSize: item.size) {
                    try? png.write(to: folder.appendingPathComponent(name), options: .atomic)
                }
            }
            try? data.write(to: sessionURL, options: .atomic)
            // もう使わない画像（閉じた画像の 10 枚を超えた分など）を消す
            let files = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            for file in files where file.hasSuffix(".png") && !keep.contains(file) {
                try? fileManager.removeItem(at: folder.appendingPathComponent(file))
            }
        }
        if wait { io.sync(execute: work) } else { io.async(execute: work) }
    }

    /// 保存した状態と画像を読む。画像のファイルがなくなっているものは除く
    func load() -> (session: SavedPinSession, images: [UUID: CGImage])? {
        guard let data = try? Data(contentsOf: sessionURL),
              var session = try? JSONDecoder().decode(SavedPinSession.self, from: data) else { return nil }
        var images: [UUID: CGImage] = [:]
        for pin in session.pins + session.closed {
            if let image = CGImage.load(contentsOf: folder.appendingPathComponent(pin.imageFileName)) {
                images[pin.id] = image
            }
        }
        session.pins.removeAll { images[$0.id] == nil }
        session.closed.removeAll { images[$0.id] == nil }
        lastSaved = data
        return (session, images)
    }

    /// 保存したものをすべて消す（戻さない設定にしたとき）
    func clear(wait: Bool = false) {
        lastSaved = nil
        let folder = folder
        let work: @Sendable () -> Void = { try? FileManager.default.removeItem(at: folder) }
        if wait { io.sync(execute: work) } else { io.async(execute: work) }
    }
}
