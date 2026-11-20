import AppKit
import AVKit
import SwiftUI

/// 録画を浮かせて、くり返し再生する窓（画像を浮かせるのと同じく、ほかのウィンドウより前に出す）。
/// 下のバーから、コピー（ファイルとして貼り付けられる）・MP4 で保存・GIF で保存・Finder で表示・閉じる、ができる
@MainActor
final class RecordingPlayer: NSObject, NSWindowDelegate {
    /// 開いている窓（閉じたら手放す）
    private static var players: [RecordingPlayer] = []

    /// 浮かせて再生している録画（古い録画を削除するときに、再生中のものは残す）
    static var openURLs: Set<URL> { Set(players.map(\.model.url)) }

    /// すべての窓を閉じる（録画をすべて削除するとき）
    static func closeAll() {
        players.forEach { $0.panel.close() }
    }

    private let panel: OverlayPanel
    private let model: RecordingPlayerModel

    /// url の録画を、録画した範囲 around のあたりに浮かせる（大きいときは画面の 7 割に縮める）
    static func show(url: URL, pointSize: CGSize, around rect: NSRect, on screen: NSScreen?) {
        let player = RecordingPlayer(url: url, pointSize: pointSize, around: rect, on: screen)
        players.append(player)
        player.panel.makeKeyAndOrderFront(nil)
    }

    private init(url: URL, pointSize: CGSize, around rect: NSRect, on screen: NSScreen?) {
        model = RecordingPlayerModel(url: url)
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let zoom = min(1, visible.width * 0.7 / max(pointSize.width, 1), visible.height * 0.7 / max(pointSize.height, 1))
        let videoSize = NSSize(width: pointSize.width * zoom, height: pointSize.height * zoom)
        let size = NSSize(width: max(videoSize.width, RecordingPlayerView.minWidth), height: videoSize.height + RecordingPlayerView.barHeight)
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)

        panel = OverlayPanel(contentRect: NSRect(origin: origin, size: size), level: AppSettings.shared.alwaysOnTop ? .floating : .normal)
        panel.isMovableByWindowBackground = true
        super.init()
        model.close = { [weak self] in self?.panel.close() }
        let hosting = FirstMouseHostingView(rootView: RecordingPlayerView(model: model, videoSize: videoSize))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        model.player.pause()
        model.cancelExport()
        Self.players.removeAll { $0 === self }
    }
}

/// 録画の窓の状態（再生・GIF を作っている途中・知らせ）
@MainActor
final class RecordingPlayerModel: ObservableObject {
    let url: URL
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    /// GIF を作っている途中の進み具合（0〜1。作っていなければ nil）
    @Published private(set) var gifProgress: Double?
    /// 操作したあとの短い知らせ
    @Published private(set) var notice: String?
    var close: () -> Void = {}
    private var exportTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
    }

    /// ファイルとしてクリップボードに入れる（Finder・チャットなどに貼り付けられる）
    func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        show("コピーしました（ファイルとして貼り付けられます）")
    }

    func saveMovie() {
        ImageSaver.saveFile(copying: url, suggestedName: url.lastPathComponent, kind: .movie, onSaved: { [weak self] in
            self?.show("保存しました")
        })
    }

    /// GIF を作って保存する（作っている間は、進み具合を出す）
    func saveGIF() {
        guard gifProgress == nil else { return }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gif")
        let name = (url.deletingPathExtension().lastPathComponent as NSString).appendingPathExtension("gif") ?? "Pinshot.gif"
        gifProgress = 0
        let source = url
        exportTask = Task { [weak self] in
            do {
                try await GIFExporter.export(videoAt: source, to: temporary) { value in
                    Task { @MainActor in self?.gifProgress = value }
                }
                guard let self, !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: temporary)
                    return
                }
                self.gifProgress = nil
                // 保存し終えたら（やめたときも）、作った一時ファイルを片付ける
                ImageSaver.saveFile(
                    copying: temporary,
                    suggestedName: name,
                    kind: .gif,
                    onSaved: { [weak self] in self?.show("GIF を保存しました") },
                    onFinish: { try? FileManager.default.removeItem(at: temporary) }
                )
            } catch {
                self?.gifProgress = nil
                try? FileManager.default.removeItem(at: temporary)
                if !(error is CancellationError) {
                    AppAlert.inform("GIF を作れませんでした", detail: error.localizedDescription)
                }
            }
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    private func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}

/// 録画の窓の中身（上に動画、下に操作のバー）
private struct RecordingPlayerView: View {
    static let barHeight: CGFloat = 40
    static let minWidth: CGFloat = 420

    @ObservedObject var model: RecordingPlayerModel
    let videoSize: NSSize

    var body: some View {
        VStack(spacing: 0) {
            PlayerLayerView(player: model.player)
                .frame(width: videoSize.width, height: videoSize.height)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                // 動画の上をドラッグすると、窓ごと動く（動画の部品がマウスを受け取ってしまうため、上に重ねる）
                .overlay(WindowDragArea().hoverRole(.movable))
                .overlay(alignment: .bottom) { noticeView }
            bar
        }
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.2)))
    }

    /// 下の操作のバー
    private var bar: some View {
        HStack(spacing: 4) {
            barButton("doc.on.doc", help: "コピー（ファイルとして貼り付けられる）", action: model.copy)
            barButton("square.and.arrow.down", help: "MP4 で保存", action: model.saveMovie)
            if let progress = model.gifProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(width: 70)
                Text("GIF を作っています")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                Button(action: model.saveGIF) {
                    Text("GIF で保存")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.4)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverHint("GIF を作って保存（長い録画は、コマを減らして軽くする）")
                .hoverRole()
            }
            barButton("folder", help: "Finder で表示", action: model.revealInFinder)
            Spacer(minLength: 8)
            // 動かすつまみ（バーの何もない所・動画の上をドラッグしても動く）
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 24, height: 24)
                .overlay(WindowDragArea())
                .hoverHint("ドラッグで動かす（動画の上やバーの何もない所をドラッグしても動く）")
                .hoverRole(.movable)
            barButton("xmark", help: "閉じる（録画は ~/Library/Application Support/Pinshot/Recordings に残る）", action: model.close)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.barHeight)
        // バーの何もない所をドラッグしても、窓ごと動く（ボタンは、その上で押せる）
        .background(WindowDragArea().hoverRole(.movable))
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHint(help)
        .hoverRole()
    }

    @ViewBuilder
    private var noticeView: some View {
        if let notice = model.notice {
            Text(notice)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.7)))
                .padding(.bottom, 10)
                .transition(.opacity)
        }
    }
}

/// 動画だけを映す（再生の操作は出さない。くり返し再生する）
private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
