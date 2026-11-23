import AppKit
import AVKit
import Combine
import SwiftUI

/// 録画を浮かせて、くり返し再生する窓（画像を浮かせるのと同じく、ほかのウィンドウより前に出す）。
/// 見た目は浮かせた画像にそろえる：動画の左上の外側に閉じるボタン（×）、動画の下に操作バー（黒い半透明の台）。
/// 操作バーから、再生・一時停止・好きな所へ動かす・音を出す、コピー（ファイルとして貼り付けられる）・MP4 で保存・GIF で保存・
/// GIF にして上げて共有リンクをコピー・Finder で表示、ができる
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
        // 窓の大きさは中身（動画・閉じるボタンの分の余白・操作バー）から決める（窓の背景は透明で、何もない所のクリックは下に通る）
        let hosting = FirstMouseHostingView(rootView: RecordingPlayerView(model: model, videoSize: videoSize))
        let size = hosting.fittingSize
        // 動画を録画した範囲の真ん中に合わせる（閉じるボタンの分の余白を除いて考える）
        let videoCenter = NSPoint(x: rect.midX, y: rect.midY)
        var origin = NSPoint(
            x: videoCenter.x - size.width / 2,
            y: videoCenter.y - (size.height - RecordingPlayerView.closeInset) + videoSize.height / 2
        )
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)

        panel = OverlayPanel(contentRect: NSRect(origin: origin, size: size), level: AppSettings.shared.alwaysOnTop ? .floating : .normal, hasShadow: false)
        super.init()
        model.close = { [weak self] in self?.panel.close() }
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        model.stop()
        Self.players.removeAll { $0 === self }
    }
}

/// 録画の窓の状態（再生・GIF を作っている途中・知らせ）
@MainActor
final class RecordingPlayerModel: ObservableObject {
    let url: URL
    let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    /// 再生しているか（開いたらすぐ再生し、最後まで行ったら頭に戻ってくり返す）
    @Published private(set) var isPlaying = true
    /// いまの位置と、録画の長さ（秒）
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    /// 録画に音が入っているか（読み込んでから決める。入っていなければ、音のボタンは押せない）
    @Published private(set) var hasAudio = false
    /// 音を消しているか（開いたらすぐ再生するので、初めは消しておく）
    @Published private(set) var isMuted = true
    /// GIF を作っている途中の進み具合（0〜1。作っていなければ nil）
    @Published private(set) var gifProgress: Double?
    /// GIF にして上げている途中か（終わるまで、上げるボタンは押せない）
    @Published private(set) var isUploading = false
    /// 操作したあとの短い知らせ
    @Published private(set) var notice: String?
    /// 動画にマウスを乗せているか（乗せている間は、浮かせた画像と同じく細い白い枠を出す）
    @Published var isHoveringVideo = false
    var close: () -> Void = {}
    private var exportTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var timeObserver: Any?
    private var statusObserver: AnyCancellable?
    /// 位置のつまみを動かしている間（いまの位置を、再生の位置で上書きしない）
    private var isScrubbing = false
    /// つまみを動かし始めたときに再生していたか（離したら、再生に戻す）
    private var resumesAfterScrub = false

    init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item)
        // 再生している位置を、操作バーの時間とつまみに出す（1 秒に 20 回）
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds.isFinite ? max(0, time.seconds) : 0
            }
        }
        statusObserver = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
        Task { [weak self] in
            let asset = AVURLAsset(url: url)
            let hasAudio = (try? await asset.loadTracks(withMediaType: .audio).isEmpty == false) ?? false
            self?.hasAudio = hasAudio
            let duration = try? await asset.load(.duration)
            guard let seconds = duration?.seconds, seconds.isFinite else { return }
            self?.duration = seconds
        }
        player.play()
    }

    // MARK: - 再生

    /// 再生・一時停止を切り替える
    func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
    }

    /// 音を出す・消すを切り替える
    func toggleMute() {
        guard hasAudio else { return }
        isMuted.toggle()
        player.isMuted = isMuted
    }

    /// 位置のつまみを動かし始めた（動かしている間は止めておく）
    func beginScrub() {
        isScrubbing = true
        resumesAfterScrub = isPlaying
        player.pause()
    }

    /// seconds の位置を出す（つまみを動かしている間、動かすたびに呼ぶ）
    func scrub(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 位置のつまみを離した（動かし始める前に再生していたら、再生に戻す）
    func endScrub() {
        isScrubbing = false
        if resumesAfterScrub { player.play() }
    }

    /// 窓を閉じたとき（再生・GIF 作り・位置の見張りを止める）
    func stop() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObserver = nil
        exportTask?.cancel()
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
        let name = (url.deletingPathExtension().lastPathComponent as NSString).appendingPathExtension("gif") ?? "Pinshot.gif"
        gifProgress = 0
        let source = url
        exportTask = Task { [weak self] in
            do {
                let temporary = try await GIFExporter.exportToTemporaryFile(videoAt: source) { value in
                    self?.gifProgress = value
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
                if !(error is CancellationError) {
                    AppAlert.inform("GIF を作れませんでした", detail: error.localizedDescription)
                }
            }
        }
    }

    /// GIF にして上げ、共有リンクをコピーする（上げる先は設定の「共有」）。
    /// 大きすぎたら小さくして作り直す・上げられなかったら知らせるのは、UploadCenter が行う
    func uploadGIF() {
        guard !isUploading else { return }
        isUploading = true
        UploadCenter.shared.shareGIF(fromMovieAt: url) { [weak self] status in
            guard let self else { return }
            self.show(status.displayText, sticky: status.isWorking)
            if !status.isWorking { self.isUploading = false }
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 短い知らせを出す（sticky なら、次の知らせを出すまで消さない。上げている途中など）
    private func show(_ text: String, sticky: Bool = false) {
        notice = text
        noticeTask?.cancel()
        guard !sticky else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}

/// 録画の窓の中身。浮かせた画像と同じ見た目にする：動画の左上の外側に閉じるボタン（×）、
/// 動画の下（間 6pt）に黒い半透明の台の操作バー、乗せている間は動画に細い白い枠、知らせは動画の真ん中
private struct RecordingPlayerView: View {
    /// 閉じるボタン（直径 20）を、丸の縁が動画の角にほぼ触れるところに出すための余白（浮かせた画像と同じ置き方）
    static let closeInset: CGFloat = 18
    /// 動画と操作バーの間（浮かせた画像と同じ）
    static let barGap: CGFloat = 6

    @ObservedObject var model: RecordingPlayerModel
    let videoSize: NSSize

    var body: some View {
        VStack(spacing: Self.barGap) {
            video
            bar
        }
        // 閉じるボタンを、動画の左上の外側に出す分の余白（左右は同じにして、操作バーを動画の真ん中にそろえる）
        .padding(.top, Self.closeInset)
        .padding(.horizontal, Self.closeInset)
    }

    /// 動画（上をドラッグすると窓ごと動く。乗せている間は細い白い枠）
    private var video: some View {
        PlayerLayerView(player: model.player)
            .frame(width: videoSize.width, height: videoSize.height)
            .background(Color.black)
            // 浮かせた画像と同じく、動画にだけ影を付ける（操作バーには付けない）
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            // 動画の上をドラッグすると、窓ごと動く（動画の部品がマウスを受け取ってしまうため、上に重ねる）
            .overlay(WindowDragArea().hoverRole(.movable))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(model.isHoveringVideo ? 0.8 : 0), lineWidth: 1))
            .overlay { noticeView }
            .overlay(alignment: .topLeading) {
                RecordingCloseButton(action: model.close)
                    .frame(width: 20, height: 20)
                    .offset(x: -Self.closeInset, y: -Self.closeInset)
            }
            .onHover { model.isHoveringVideo = $0 }
    }

    /// 下の操作バー（浮かせた画像の操作バーと同じ台・同じボタン）。台の何もない所をドラッグしても、窓ごと動く
    private var bar: some View {
        HStack(spacing: 2) {
            moveHandle
            QuickActionDivider()
            QuickActionButton(
                symbol: model.isPlaying ? "pause.fill" : "play.fill",
                help: model.isPlaying ? "一時停止" : "再生（最後まで行ったら、頭に戻ってくり返す）",
                action: model.togglePlay
            )
            Text("\(RecordingRules.elapsedText(model.currentTime)) / \(RecordingRules.elapsedText(model.duration))")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                // 長さが 10 分（上限）になっても、バーの幅が変わらないように
                .frame(width: 80)
            Slider(
                value: Binding(get: { model.currentTime }, set: { model.scrub(to: $0) }),
                in: 0...max(model.duration, 0.01),
                onEditingChanged: { editing in editing ? model.beginScrub() : model.endScrub() }
            )
            .controlSize(.mini)
            .tint(.white)
            .frame(width: 120)
            .padding(.horizontal, 4)
            .hoverHint("ドラッグで、見たい所へ動かす")
            .hoverRole()
            muteButton
            QuickActionDivider()
            QuickActionButton(symbol: "doc.on.doc", help: "コピー（ファイルとして貼り付けられる）", action: model.copy)
            QuickActionButton(symbol: "square.and.arrow.down", help: "MP4 で保存", action: model.saveMovie)
            gifButton
            QuickActionButton(
                symbol: "link",
                help: "GIF にして \(UploadDestinations.current?.id.label ?? "上げる先") に上げ、共有リンクをコピー（上げる先は設定の「共有」。大きいときは小さくして上げる。音は入らない）",
                action: model.uploadGIF
            )
            .disabled(model.isUploading)
            .opacity(model.isUploading ? 0.4 : 1)
            QuickActionButton(symbol: "folder", help: "Finder で表示", action: model.revealInFinder)
        }
        .quickActionBarBackground()
        // 台の何もない所（縁まで）をドラッグしても、窓ごと動く（ボタン・つまみは、その上で押せる）
        .background(WindowDragArea().clipShape(Capsule()).hoverRole(.movable))
    }

    /// 動かすつまみ ✙（浮かせた画像の操作バーと同じく、左端に置く）。動画の上・バーの何もない所をドラッグしても動く
    private var moveHandle: some View {
        QuickActionMoveIcon()
            .overlay(WindowDragArea())
            .hoverHint("ドラッグで録画の窓を移動（動画の上やバーの何もない所をドラッグしても動く）")
            .hoverRole(.movable)
    }

    /// 音を出す・消す（音の入っていない録画では押せない。録画ごとにバーの幅が変わらないよう、いつも出しておく）
    private var muteButton: some View {
        QuickActionButton(
            symbol: model.hasAudio && !model.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
            help: model.hasAudio ? (model.isMuted ? "音を出す" : "音を消す") : "この録画には音が入っていません（録画の音は、範囲を選ぶ画面の下のバーか、メニューバーの「録画の音」で選ぶ）",
            action: model.toggleMute
        )
        .opacity(model.hasAudio ? 1 : 0.4)
    }

    /// GIF で保存（作っている間は、同じ幅に進み具合を出す。バーの幅が変わらないように）
    @ViewBuilder
    private var gifButton: some View {
        if let progress = model.gifProgress {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.white)
                .frame(width: 60)
                .frame(width: 76, height: 22)
                .hoverHint("GIF を作っています")
        } else {
            Button(action: model.saveGIF) {
                Text("GIF で保存")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(width: 76, height: 22)
                    .background(Capsule().strokeBorder(Color.white.opacity(0.4)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .hoverHint("GIF を作って保存（音は入らない。長い録画は、コマを減らして軽くする）")
            .hoverRole()
        }
    }

    /// 操作したあとの短い知らせ（浮かせた画像のお知らせと同じく、動画の真ん中に出す）
    @ViewBuilder
    private var noticeView: some View {
        if let notice = model.notice {
            Text(notice)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.7)))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// 閉じるボタン（浮かせた画像の左上の外側の × と同じ部品）
private struct RecordingCloseButton: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> PinCloseButton {
        let button = PinCloseButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        button.hint = "閉じる（録画は ~/Library/Application Support/Pinshot/Recordings に残る）"
        button.onClick = action
        return button
    }

    func updateNSView(_ button: PinCloseButton, context: Context) {
        button.onClick = action
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
