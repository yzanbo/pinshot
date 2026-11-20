import AppKit
import Combine
import SwiftUI

/// 浮かせた画像 1 枚ぶんの操作（拡大縮小・透明度・編集モード・コピー・保存）
@MainActor
final class PinController: NSObject, NSWindowDelegate {
    let panel: PinPanel
    let canvas: PinCanvasView
    let state: EditorState
    let appearance: PinAppearance
    /// ウィンドウの中身（背景を付けるときは背景を描き、その中に画像を置く）
    private let backdrop = PinBackdropView()
    /// いまウィンドウに付けている余白（拡大前のポイント）
    private var appliedPadding: CGFloat = 0
    var onClose: ((PinController) -> Void)?

    /// 編集ツールバー（編集モードの間だけ出す）
    private let toolbar: PinToolbarController
    private(set) var zoom: CGFloat = 1 {
        // 操作バー・ツールバーの拡大率の表示に知らせる
        didSet { appearance.zoom = Double(zoom) }
    }
    private var cancellables = Set<AnyCancellable>()

    /// クリックを下のアプリに通しているか
    private(set) var isClickThrough = false
    /// クリック透過にする前の不透明度（透過にすると薄くするので、残すときはこの値を使う）
    private var opacityBeforeClickThrough: CGFloat?

    /// 残すときの不透明度（クリック透過は戻さないので、透過にする前の不透明度）
    var restorableOpacity: CGFloat {
        isClickThrough ? (opacityBeforeClickThrough ?? panel.alphaValue) : panel.alphaValue
    }

    /// この画像だけ最前面の設定を変えているとき（nil なら設定に従う）
    private var onTopOverride: Bool?
    /// どの履歴の画像か（履歴から同じ画像を浮かせたときに、増やさず前に出すため）
    var origin: PinOrigin?

    var isOnTop: Bool { onTopOverride ?? AppSettings.shared.alwaysOnTop }

    /// 閉じた画像を戻すとき・終了後に戻すときに引き継ぐ状態（画像そのものは別に持つ）
    var savedPin: SavedPin {
        SavedPin(
            id: id,
            imageSize: canvas.imageSize,
            frame: contentScreenFrame,
            zoom: zoom,
            opacity: restorableOpacity,
            snapshot: canvas.snapshot,
            backdrop: state.savedBackdrop,
            onTopOverride: onTopOverride,
            origin: origin
        )
    }

    /// 画像ごとの印（終了・再起動のあとも残すときの、画像のファイル名に使う）
    let id: UUID

    /// restoring: 閉じた画像・終了前の画像を戻すときの状態（書き込み・トリミング・背景・最前面の設定を引き継ぐ）
    init(id: UUID = UUID(), image: CGImage, imageSize: CGSize, frame: NSRect, zoom: CGFloat = 1, restoring: SavedPin? = nil) {
        self.id = id
        let state = EditorState()
        self.state = state
        self.appearance = PinAppearance(opacity: AppSettings.shared.defaultOpacity, zoom: Double(zoom))
        let panel = PinPanel(contentRect: frame)
        self.panel = panel
        self.canvas = PinCanvasView(image: image, imageSize: imageSize, state: state)
        self.toolbar = PinToolbarController(pinPanel: panel, state: state)
        super.init()
        self.zoom = zoom

        if let restoring {
            canvas.restore(restoring.snapshot)
            state.restoreBackdrop(restoring.backdrop)
            onTopOverride = restoring.onTopOverride
            origin = restoring.origin
        }
        canvas.controller = self
        canvas.frame = NSRect(origin: .zero, size: frame.size)
        backdrop.frame = NSRect(origin: .zero, size: frame.size)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.controller = self
        backdrop.content = canvas
        backdrop.zoom = zoom
        backdrop.addSubview(canvas)
        panel.contentView = backdrop
        panel.delegate = self
        // 背景を付ける設定なら、画像の位置はそのままで、まわりに余白を広げる
        applyBackdrop()
        panel.alphaValue = AppSettings.shared.defaultOpacity
        applyLevel()

        observeChanges()
    }

    /// 編集の状態・設定が変わったら、画像とツールバーに反映する
    private func observeChanges() {
        // @Published は変更前に通知されるので、次の周回で反映する
        state.$tool
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.canvas.toolDidChange() }
            .store(in: &cancellables)
        // 色・太さ・各ツールのオプションを変えたら、入力中の文字・選んでいる書き込みに、変えた項目だけを反映する
        Publishers.MergeMany([
            state.$color.dropFirst().map { _ in StyleAspects.color }.eraseToAnyPublisher(),
            state.$opacity.dropFirst().map { _ in StyleAspects.opacity }.eraseToAnyPublisher(),
            state.$lineWidths.dropFirst().map { _ in StyleAspects.lineWidth }.eraseToAnyPublisher(),
            state.$rectangleStyle.dropFirst().map { _ in StyleAspects.rectangle }.eraseToAnyPublisher(),
            state.$ellipseStyle.dropFirst().map { _ in StyleAspects.ellipse }.eraseToAnyPublisher(),
            state.$arrowStyle.dropFirst().map { _ in StyleAspects.arrow }.eraseToAnyPublisher(),
            state.$counterSize.dropFirst().map { _ in StyleAspects.counter }.eraseToAnyPublisher(),
            state.$counterStyle.dropFirst().map { _ in StyleAspects.counter }.eraseToAnyPublisher(),
            state.$textStyle.dropFirst().map { _ in StyleAspects.text }.eraseToAnyPublisher(),
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] aspects in self?.canvas.applyStyleToSelection(aspects: aspects) }
        .store(in: &cancellables)

        // ボタンにマウスを乗せたら、説明をポップアップで出す
        state.$hoverHint
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hint in self?.toolbar.updateHint(hint) }
            .store(in: &cancellables)
        // ツールや選択が変わったら、前の説明は消す（消えたボタンの説明が残らないように）。
        // 2 行目も、背景のオプションからツールのオプションに戻す
        Publishers.Merge3(
            state.$tool.dropFirst().map { _ in () },
            state.$selectionTool.dropFirst().map { _ in () },
            state.$isEditingText.dropFirst().filter { $0 }.map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.state.hoverHint = nil
            if self?.state.showsBackdropOptions == true {
                self?.state.showsBackdropOptions = false
            }
        }
        .store(in: &cancellables)
        // 文字の大きさは、入力中の文字にもすぐ反映する
        state.$fontSize
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.canvas.fontSizeDidChange() }
            .store(in: &cancellables)
        // ツールバーの大きさが変わったら（オプションの行が増えた・減ったなど）並べ直す
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.toolbar.fitSize() }
            .store(in: &cancellables)
        // ツールバーを切り離す・画像に付ける
        state.$isDetached
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.toolbar.applyAttachment() }
            .store(in: &cancellables)

        // 設定（× ボタンの出し方・影）を変えたら、浮かせている画像にもすぐ反映する
        AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.canvas.updateChrome()
                self?.applyLevel()
                self?.state.followBackdropSettings(AppSettings.shared.exportDecoration)
            }
            .store(in: &cancellables)

        // 背景の有無・見た目が変わったら反映する（ツールバー・右クリック・設定のどれから変えても）
        state.$backdropShown.combineLatest(state.$backdropDecoration)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyBackdrop() }
            .store(in: &cancellables)
        state.$backdropShown
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shown in
                self?.canvas.showHUD(shown ? "背景を付けました（書き出しも同じ見た目）" : "背景を外しました")
            }
            .store(in: &cancellables)
    }

    // MARK: - 背景（書き出しと同じ見た目を、画面の上でも見せる）

    /// この画像に背景を付けて表示・書き出すか
    var showsBackdrop: Bool { state.backdropShown }

    /// 背景を付けたときの余白を含めた、画像の大きさ（拡大前のポイント）
    private var paddedContentSize: CGSize {
        let size = canvas.contentSize
        return CGSize(width: size.width + appliedPadding * 2, height: size.height + appliedPadding * 2)
    }

    /// 画像（キャンバス）の画面上の位置（背景の余白を除いた部分）
    var contentScreenFrame: NSRect {
        panel.frame.insetBy(dx: appliedPadding * zoom, dy: appliedPadding * zoom)
    }

    /// 背景の有無・見た目を反映する。画像の位置は動かさず、まわりの余白だけを広げたり縮めたりする
    private func applyBackdrop() {
        let decoration = state.backdropDecoration
        let newPadding = showsBackdrop ? decoration.padding.points : 0
        let contentFrame = contentScreenFrame
        backdrop.decoration = showsBackdrop ? decoration : nil
        backdrop.zoom = zoom
        guard abs(newPadding - appliedPadding) > 0.01 else {
            backdrop.needsLayout = true
            return
        }
        appliedPadding = newPadding
        panel.setFrame(contentFrame.insetBy(dx: -newPadding * zoom, dy: -newPadding * zoom), display: true)
        backdrop.needsLayout = true
        toolbar.layout()
    }

    func setBackdropShown(_ shown: Bool) {
        state.setBackdropShown(shown)
    }

    /// 最前面に出すかどうかを、ウィンドウの階層に反映する
    private func applyLevel() {
        let level: NSWindow.Level = isOnTop ? .floating : .normal
        guard panel.level != level else { return }
        panel.level = level
        toolbar.updateLevel()
        // 画像の外に出している部品も、同じ階層にそろえる
        canvas.updateChrome()
    }

    func setOnTop(_ onTop: Bool) {
        onTopOverride = onTop == AppSettings.shared.alwaysOnTop ? nil : onTop
        applyLevel()
        panel.orderFrontRegardless()
        canvas.showHUD(onTop ? "最前面に表示" : "最前面に表示しない")
    }

    func bringToFront() {
        panel.orderFrontRegardless()
        // 画面に出たので、閉じるボタン・操作バーを出し直す（マウスを乗せる前から、設定どおりに出す）
        canvas.updateChrome()
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(canvas)
        canvas.updateChrome()
    }

    func close() {
        canvas.commitPendingText()
        canvas.textResultPopover?.close()
        toolbar.hide()
        canvas.hideOutsideParts()
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        // space を押したままほかへ移ると keyUp が届かないので、押していない状態に戻す
        canvas.releaseHeldKeys()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        // 別の画面へ動かしたら、ツールバーをその画面に収まる位置に置き直す
        toolbar.layout()
    }

    /// ドラッグで動かし終えたとき
    func windowDidFinishMoving() {
        relayoutAttachedParts()
    }

    func windowDidMove(_ notification: Notification) {
        relayoutAttachedParts()
    }

    func windowDidResize(_ notification: Notification) {
        relayoutAttachedParts()
    }

    /// 動かしている間・拡大縮小したときに、ツールバーと操作バーを置き直す
    /// （画像の下に余白がなくなったら、画面のいちばん下へ移す）
    private func relayoutAttachedParts() {
        toolbar.layout()
        canvas.repositionOutsideParts()
    }

    // MARK: - 編集モード

    func toggleEditing() {
        setEditing(!state.isEditing)
    }

    func setEditing(_ editing: Bool) {
        guard state.isEditing != editing else { return }
        if !editing {
            canvas.commitPendingText()
        }
        state.isEditing = editing
        if editing {
            // アプリ全体は前に出さない（ほかの画像まで前に出てしまうため）。この画像のウィンドウだけをキーにする
            toolbar.show(actions: makeToolbarActions(), appearance: appearance)
            panel.makeKey()
            panel.makeFirstResponder(canvas)
        } else {
            toolbar.hide()
        }
        canvas.toolDidChange()
        canvas.updateChrome()
        canvas.showHUD(editing ? "編集モード" : "編集を終えました")
    }

    private func makeToolbarActions() -> ToolbarActions {
        ToolbarActions(
            undo: { [weak self] in self?.canvas.undo() },
            redo: { [weak self] in self?.canvas.redo() },
            copy: { [weak self] in self?.copyToPasteboard() },
            save: { [weak self] in self?.save() },
            copyText: { [weak self] in self?.copyRecognizedText() },
            copyTextInRegion: { [weak self] in self?.canvas.beginPickingTextRegion() },
            done: { [weak self] in self?.setEditing(false) },
            setOpacity: { [weak self] value in self?.setOpacity(CGFloat(value)) },
            setZoom: { [weak self] value in self?.setZoom(CGFloat(value)) },
            openHistory: { CaptureHistoryWindowController.shared.show() },
            move: { [weak self] in self?.toolbar.moveWithMouse() },
            endMove: { [weak self] in self?.toolbar.endMoveWithMouse() }
        )
    }

    // MARK: - 移動

    /// 矢印キーで少しずつ動かす
    func moveBy(dx: CGFloat, dy: CGFloat) {
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        toolbar.layout()
    }

    /// 画面から外れていたら、見える画面の中に戻す（ディスプレイを外したときなど）
    func ensureOnScreen() {
        canvas.commitPendingText()
        let frame = panel.frame
        let visibleScreens = NSScreen.screens.map(\.visibleFrame)
        let isVisible = visibleScreens.contains { $0.intersection(frame).width >= 40 && $0.intersection(frame).height >= 40 }
        guard !isVisible, let target = NSScreen.main?.visibleFrame ?? visibleScreens.first else { return }

        // 画面より大きければ縮める
        let fit = min(1, target.width * 0.9 / frame.width, target.height * 0.9 / frame.height)
        if fit < 1 {
            zoom *= fit
            backdrop.zoom = zoom
        }
        let size = NSSize(width: frame.width * fit, height: frame.height * fit)
        panel.setFrame(
            NSRect(x: target.midX - size.width / 2, y: target.midY - size.height / 2, width: size.width, height: size.height),
            display: true
        )
        toolbar.layout()
    }

    // MARK: - 拡大縮小・トリミング・透明度

    private var minZoom: CGFloat {
        let size = canvas.contentSize
        return max(0.05, 24 / max(min(size.width, size.height), 1))
    }

    private static let maxZoom: CGFloat = 8

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), Self.maxZoom)
    }

    func zoom(by factor: CGFloat, around anchor: NSPoint) {
        setZoom(zoom * factor, around: anchor)
    }

    /// 拡大率を value にする（anchor（スクリーン座標）の位置を動かさない。nil なら画像の真ん中）
    func setZoom(_ value: CGFloat, around anchor: NSPoint? = nil) {
        let newZoom = clampedZoom(value)
        guard abs(newZoom - zoom) > 0.0001 else { return }
        let frame = panel.frame
        applyZoom(newZoom, anchor: anchor ?? NSPoint(x: frame.midX, y: frame.midY), baseFrame: frame)
    }

    /// ツールバーのつまみで画像を動かしている最中か（その間は、画像の上でもカーソルをつかんだ手のままにする）
    var isMovingWithToolbarHandle: Bool { toolbar.isMovingWithHandle }

    func resetZoom() {
        setZoom(1)
    }

    /// 端のドラッグで大きさを変える（縦横比を保ち、反対側の端は動かさない）
    func resize(with drag: EdgeResizeDrag) {
        let target = drag.target()
        let newZoom = clampedZoom(target.width / max(paddedContentSize.width, 1))
        applyZoom(newZoom, anchor: target.anchor, baseFrame: drag.startFrame)
    }

    /// anchor（スクリーン座標）の位置が動かないように大きさを変える
    private func applyZoom(_ newZoom: CGFloat, anchor: NSPoint, baseFrame: NSRect) {
        // 入力中の文字は、いまの拡大率で大きさを決めているので、先に確定する
        canvas.commitPendingText()
        let fx = (anchor.x - baseFrame.minX) / baseFrame.width
        let fy = (anchor.y - baseFrame.minY) / baseFrame.height
        let size = paddedContentSize
        let newSize = CGSize(width: size.width * newZoom, height: size.height * newZoom)
        let origin = NSPoint(x: anchor.x - fx * newSize.width, y: anchor.y - fy * newSize.height)
        zoom = newZoom
        backdrop.zoom = newZoom
        panel.setFrame(NSRect(origin: origin, size: newSize), display: true)
        toolbar.layout()
        canvas.showHUD(newZoom.percentText)
    }

    /// トリミングの範囲が変わったら、画面上で絵が動かないようにウィンドウの位置と大きさを合わせる
    func cropDidChange(from old: CGRect, to new: CGRect) {
        let frame = panel.frame
        let x = frame.minX + (new.minX - old.minX) * zoom
        let top = frame.maxY - (new.minY - old.minY) * zoom
        let size = NSSize(width: (new.width + appliedPadding * 2) * zoom, height: (new.height + appliedPadding * 2) * zoom)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        toolbar.layout()
    }

    /// showsHUD: 「不透明度 80%」を出す（戻すときなど、出さないこともある）
    func setOpacity(_ value: CGFloat, showsHUD: Bool = true) {
        panel.alphaValue = min(max(value, 0.1), 1)
        appearance.opacity = Double(panel.alphaValue)
        guard showsHUD else { return }
        canvas.showHUD("不透明度 \(panel.alphaValue.percentText)", progress: Double(panel.alphaValue))
    }

    func adjustOpacity(by delta: CGFloat) {
        setOpacity(panel.alphaValue + delta)
    }

    /// クリックを下のアプリに通す（なぞって描くときなどに）。戻すときはメニューバーから
    func setClickThrough(_ enabled: Bool) {
        if enabled, !isClickThrough {
            opacityBeforeClickThrough = panel.alphaValue
        }
        isClickThrough = enabled
        if !enabled { opacityBeforeClickThrough = nil }
        if enabled {
            setEditing(false)
            if panel.alphaValue > 0.7 {
                setOpacity(0.6)
            }
            canvas.showHUD("クリック透過中（メニューバーから解除）")
        }
        panel.ignoresMouseEvents = enabled
        canvas.updateChrome()
    }
}
