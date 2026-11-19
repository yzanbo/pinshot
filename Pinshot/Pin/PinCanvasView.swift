import AppKit
import SwiftUI

/// 浮かせた画像の中身。画像と書き込みを描き、マウス・キーの操作を受ける。
///
/// 役割ごとにファイルを分けている（どれもこのクラスの extension）:
/// - `PinCanvasView.swift`: 状態・座標の変換・× や操作バー・描画・書き出し
/// - `+Cursor`: カーソルの形
/// - `+Mouse`: マウスの操作（描く・動かす・つまみ・トリミング・拡大縮小・ドラッグで書き出す）
/// - `+Keyboard`: キーの操作
/// - `+Selection`: 選択と、色・大きさの反映、複製・重なり順
/// - `+History`: 元に戻す・やり直す
/// - `+Text`: 文字の入力
///
/// 書き込み・トリミング・元に戻す履歴は `document`（AnnotationDocument）が持つ。変えるときは必ず document のメソッドを通す
final class PinCanvasView: NSView, NSTextFieldDelegate, NSDraggingSource {
    let baseImage: CGImage
    /// 元の画像の大きさ（ポイント）。書き込みの座標はこの画像が基準
    let imageSize: CGSize
    let state: EditorState
    weak var controller: PinController?

    private let settings = AppSettings.shared
    private let baseNSImage: NSImage
    private lazy var pixelatedImage: NSImage? = ImageEffects.pixelated(baseImage, size: imageSize)
    private lazy var blurredImage: NSImage? = ImageEffects.blurred(baseImage, size: imageSize)

    /// 書き込みに必要な加工画像（モザイク・ぼかしがあるときだけ作る）
    private func effects(for list: [Annotation]) -> EffectImages {
        EffectImages(
            pixelated: list.contains(where: \.isMosaic) ? pixelatedImage : nil,
            blurred: list.contains(where: \.isBlur) ? blurredImage : nil
        )
    }

    /// 書き込み・トリミング・元に戻す履歴
    var document: AnnotationDocument

    /// 書き込み（読むだけ。変えるときは document を通す）
    var annotations: [Annotation] { document.annotations }
    /// 表示している範囲（画像のポイント座標）
    var cropRect: CGRect { document.cropRect }

    /// 表示している大きさ（トリミング後、ポイント）
    var contentSize: CGSize { cropRect.size }

    var snapshot: EditSnapshot { document.snapshot }

    // ドラッグ中の書き込み・トリミング
    var drafting: Annotation?
    var dragStart: CGPoint?
    var cropDraft: CGRect?

    // 選択ツールで選んでいる書き込みと、動かしている途中の情報
    /// 選んでいる書き込み（選んだ順）。⌘A・shift + クリックで複数選べる
    var selection: [UUID] = [] {
        didSet { selectionDidChange() }
    }

    /// 1 つだけ選んでいるときの書き込み（つまみ・文字の直しなどに使う）
    var selectedID: UUID? {
        get { selection.count == 1 ? selection[0] : nil }
        set { selection = newValue.map { [$0] } ?? [] }
    }
    var moveStart: CGPoint?
    /// 動かし始めたときの、選んでいる書き込み
    var moveOriginals: [UUID: Annotation] = [:]
    var didMove = false

    // 文字の入力
    var textField: NSTextField?
    var textOrigin: CGPoint = .zero
    var textColor: RGBAColor = .red
    var textFontSize: CGFloat = FontSizes.default
    var textStyle = TextStyle()
    /// ツールバーの文字の大きさを、表示を合わせるためだけに変えた回数（その通知では文字を変えない）
    var silentFontSizeChanges = 0
    var selectionObserver: Any?
    var textCancelled = false
    /// クリックで文字の入力が終わったときの、そのクリックの時刻（同じクリックで新しく描き始めないため）
    var textEndingClickTimestamp: TimeInterval?
    /// 書いた文字を直しているときの、元の位置と元の文字
    var reEditIndex: Int?
    var reEditOriginal: Annotation?

    /// 選んだ書き込みのつまみをドラッグしているとき（つかんだつまみと、つかむ前の書き込み）
    var handleDrag: (handle: EditHandle, original: Annotation)?
    var handleChanged = false

    /// 端をつかんで大きさを変えている間の状態
    var edgeResize: EdgeResizeDrag?

    /// space を押している間はドラッグで画像を動かす
    var isSpaceHeld = false
    private var isHovering = false
    let closeButton = PinCloseButton(frame: NSRect(x: 6, y: 6, width: 20, height: 20))
    private let hud = HUDView(frame: .zero)
    var quickBar: FirstMouseHostingView<QuickActionBar>?
    private var quickBarStyle: QuickBarStyle = .full
    var selectionBar: NSView?

    init(image: CGImage, imageSize: CGSize, state: EditorState) {
        self.baseImage = image
        self.imageSize = imageSize
        self.state = state
        self.baseNSImage = NSImage(cgImage: image, size: imageSize)
        self.document = AnnotationDocument(imageSize: imageSize)
        super.init(frame: NSRect(origin: .zero, size: imageSize))

        // 左上に固定（flipped なので下の余白を伸ばす）
        closeButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        closeButton.onClick = { [weak self] in self?.controller?.close() }
        addSubview(closeButton)

        addSubview(hud)
        updateChrome()
    }

    /// マウスを乗せたときの操作バー（コントローラーをつないだあとに作る）
    private func makeQuickBarIfNeeded() {
        guard quickBar == nil, let controller else { return }
        let bar = FirstMouseHostingView(rootView: makeQuickActionBar(appearance: controller.appearance, style: quickBarStyle))
        bar.frame.size = bar.fittingSize
        // 下の真ん中に固定（flipped なので上の余白を伸ばす）
        bar.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        bar.isHidden = true
        addSubview(bar, positioned: .below, relativeTo: hud)
        quickBar = bar
    }

    /// 選んだ書き込みの上に、複製・前面・背面・削除のバーを出す（動かしている間・文字の入力中は隠す）
    func updateSelectionBar() {
        let shouldShow = state.isEditing && !selection.isEmpty && moveStart == nil && handleDrag == nil && textField == nil
        guard shouldShow else {
            selectionBar?.isHidden = true
            return
        }
        if selectionBar == nil {
            let bar = FirstMouseHostingView(rootView: SelectionActionBar(
                duplicate: { [weak self] in self?.duplicateSelected() },
                bringForward: { [weak self] in self?.reorderSelected(forward: true) },
                sendBackward: { [weak self] in self?.reorderSelected(forward: false) },
                delete: { [weak self] in self?.deleteSelected() }
            ))
            bar.frame.size = bar.fittingSize
            addSubview(bar, positioned: .below, relativeTo: hud)
            selectionBar = bar
        }
        guard let bar = selectionBar else { return }
        let rects = selectedIndices.map { viewRect(annotations[$0].bounds) }
        guard let first = rects.first else { return }
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        let size = bar.frame.size
        var x = union.midX - size.width / 2
        x = min(max(x, 4), max(4, bounds.width - size.width - 4))
        // 上に置けなければ下、それも無理なら画像の上端の内側
        var y = union.minY - size.height - 10
        if y < 4 { y = union.maxY + 10 }
        if y + size.height > bounds.height - 4 { y = 4 }
        bar.frame.origin = NSPoint(x: x.rounded(), y: y.rounded())
        bar.isHidden = false
    }

    private func makeQuickActionBar(appearance: PinAppearance, style: QuickBarStyle) -> QuickActionBar {
        QuickActionBar(
            appearance: appearance,
            style: style,
            edit: { [weak self] in self?.controller?.setEditing(true) },
            setOpacity: { [weak self] value in self?.controller?.setOpacity(CGFloat(value)) },
            copy: { [weak self] in self?.controller?.copyToPasteboard() },
            save: { [weak self] in self?.controller?.save() },
            more: { [weak self] in self?.showContextMenuFromQuickBar() }
        )
    }

    /// 形ごとの操作バーの大きさ（一度だけ測る）
    private static var quickBarSizes: [QuickBarStyle: NSSize] = [:]

    private static func quickBarSize(_ style: QuickBarStyle) -> NSSize {
        if let size = quickBarSizes[style] { return size }
        let probe = NSHostingView(rootView: QuickActionBar(
            appearance: PinAppearance(opacity: 1),
            style: style,
            edit: {}, setOpacity: { _ in }, copy: {}, save: {}, more: {}
        ))
        let size = probe.fittingSize
        quickBarSizes[style] = size
        return size
    }

    /// 画像の大きさに入りきる中で、いちばん多くのボタンを出せる形を選ぶ（入らなくても、編集ボタンだけは出す）
    private func fittingQuickBarStyle() -> QuickBarStyle {
        for style in QuickBarStyle.widestFirst where style != .minimal {
            let size = Self.quickBarSize(style)
            // 文字付きの形は、画像の下の方に置いても絵を隠しすぎない高さがあるときだけ
            let neededHeight = style == .compact ? size.height + 12 : size.height + 40
            if bounds.width >= size.width + 16, bounds.height >= neededHeight {
                return style
            }
        }
        return .minimal
    }

    private func layoutQuickBar() {
        guard let bar = quickBar else { return }
        let size = bar.frame.size
        // 低い画像では下の余白を詰める（それでも入らなければ上下の真ん中）
        let bottom = min(8, max(0, (bounds.height - size.height) / 2))
        bar.frame.origin = NSPoint(
            x: ((bounds.width - size.width) / 2).rounded(),
            y: (bounds.height - size.height - bottom).rounded()
        )
    }

    private func showContextMenuFromQuickBar() {
        guard let bar = quickBar, let menu = controller?.makeContextMenu() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: bar.frame.maxX - 20, y: bar.frame.minY), in: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 閉じた画像を戻すとき、書き込みとトリミングを戻す
    func restore(_ snapshot: EditSnapshot) {
        document.restore(snapshot)
        state.nextCounterNumber = document.nextCounterNumber
        needsDisplay = true
    }

    // MARK: - 座標

    /// 画面上の 1 ポイントが、画像の何ポイントにあたるか（拡大縮小のぶん）
    var scaleFactor: CGFloat { bounds.width / max(cropRect.width, 1) }

    /// ビューの座標 → 画像の座標
    func imagePoint(_ viewPoint: NSPoint, clamp: Bool = true) -> CGPoint {
        var x = viewPoint.x / scaleFactor + cropRect.minX
        var y = viewPoint.y / scaleFactor + cropRect.minY
        if clamp {
            x = min(max(x, cropRect.minX), cropRect.maxX)
            y = min(max(y, cropRect.minY), cropRect.maxY)
        }
        return CGPoint(x: x, y: y)
    }

    func imagePoint(for event: NSEvent) -> CGPoint {
        imagePoint(convert(event.locationInWindow, from: nil))
    }

    /// 画像の座標の四角 → ビューの座標の四角
    func viewRect(_ rect: CGRect) -> NSRect {
        NSRect(
            x: (rect.minX - cropRect.minX) * scaleFactor,
            y: (rect.minY - cropRect.minY) * scaleFactor,
            width: rect.width * scaleFactor,
            height: rect.height * scaleFactor
        )
    }

    var selectedIndices: [Int] {
        selection.compactMap { id in annotations.firstIndex { $0.id == id } }
    }

    private func selectionDidChange() {
        let tools = Set(selectedIndices.map { annotations[$0].tool })
        state.selectionTool = tools.count == 1 ? tools.first : nil
        updateSelectionBar()
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return annotations.firstIndex { $0.id == selectedID }
    }

    func hitAnnotation(at point: CGPoint) -> Int? {
        // 画面上で約 5pt 以内なら当たりにする
        let tolerance = 5 / scaleFactor
        return annotations.lastIndex { $0.hitTest(point, tolerance: tolerance) }
    }

    // MARK: - 見た目（× ボタン・枠・HUD）

    /// ×・編集ボタン・操作バーの表示を、設定・マウスの位置・編集中かどうかに合わせる
    func updateChrome() {
        let visible: Bool = switch settings.closeButtonMode {
        case .always: true
        case .hover: isHovering
        case .hidden: false
        }
        closeButton.isHidden = !(visible && bounds.width >= 44 && bounds.height >= 32 && !state.isEditing)

        if settings.showsQuickActions { makeQuickBarIfNeeded() }
        if let bar = quickBar {
            // 狭いときも消さずに、ボタンを減らした形にする（編集ボタンはいつも残す）
            let style = fittingQuickBarStyle()
            if style != quickBarStyle, let controller {
                quickBarStyle = style
                bar.rootView = makeQuickActionBar(appearance: controller.appearance, style: style)
                bar.frame.size = bar.fittingSize
            }
            bar.isHidden = !(settings.showsQuickActions && visible && !state.isEditing)
            layoutQuickBar()
        }
        updateSelectionBar()
        needsDisplay = true
    }

    func showHUD(_ text: String, progress: Double? = nil) {
        hud.show(text, progress: progress, in: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateChrome()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea([.mouseEnteredAndExited, .mouseMoved, .cursorUpdate])
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateChrome()
        updateCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor()
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor()
    }

    override func flagsChanged(with event: NSEvent) {
        // ⌥・⌘ を押した・離したときにカーソルを変える
        updateCursor()
        super.flagsChanged(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateChrome()
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        // トリミングしているときは、元の画像をずらして描き、はみ出した所はビューの外に出す
        baseNSImage.draw(
            in: viewRect(CGRect(origin: .zero, size: imageSize)),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        )

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let shadow = settings.annotationShadow
        ctx.saveGState()
        ctx.scaleBy(x: scaleFactor, y: scaleFactor)
        ctx.translateBy(x: -cropRect.minX, y: -cropRect.minY)
        let all = drafting.map { annotations + [$0] } ?? annotations
        AnnotationRenderer.draw(all, in: ctx, imageSize: imageSize, effects: effects(for: all), shadow: shadow)
        ctx.restoreGState()

        if let cropDraft {
            drawCropDraft(viewRect(cropDraft))
        }

        if state.isEditing {
            // 編集中はアクセントカラーの枠
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()

            // 選んでいる書き込みを点線で囲む
            if let index = selectedIndex, !annotations[index].editHandles.isEmpty {
                // つまみ（白い四角）
                for (_, point) in annotations[index].editHandles {
                    let p = viewRect(CGRect(origin: point, size: .zero)).origin
                    let square = NSRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
                    NSColor.white.setFill()
                    NSBezierPath(rect: square).fill()
                    NSColor.controlAccentColor.setStroke()
                    let border = NSBezierPath(rect: square.insetBy(dx: 0.5, dy: 0.5))
                    border.lineWidth = 1
                    border.stroke()
                }
            } else {
                for index in selectedIndices {
                    let path = NSBezierPath(rect: viewRect(annotations[index].bounds).insetBy(dx: -5, dy: -5))
                    path.lineWidth = 1
                    path.setLineDash([4, 3], count: 2, phase: 0)
                    NSColor.controlAccentColor.setStroke()
                    path.stroke()
                }
            }
        } else if isHovering {
            // マウスを乗せている間は、背景と見分けやすいよう細い枠を出す
            NSColor.white.withAlphaComponent(0.6).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }

    /// トリミングする範囲の外を暗くする
    private func drawCropDraft(_ rect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: rect))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.white.setStroke()
        border.stroke()
    }

    // MARK: - 書き出し

    func renderedImage() -> CGImage? {
        ImageExporter.render(
            base: baseImage,
            imageSize: imageSize,
            annotations: annotations,
            effects: effects(for: annotations),
            shadow: settings.annotationShadow,
            crop: cropRect
        )
    }
}
