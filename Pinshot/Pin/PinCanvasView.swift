import AppKit
import SwiftUI

/// 浮かせた画像の中身。画像と書き込みを描き、マウス・キーの操作を受ける。
///
/// 役割ごとにファイルを分けている（どれもこのクラスの extension）:
/// - `PinCanvasView.swift`: 状態・座標の変換・× や操作バーを出すかどうか・描画・書き出し
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
    /// 文字を読み取る範囲を選んでいるか（右クリックの「範囲を選んで文字をコピー」）と、ドラッグしている範囲
    var isPickingTextRegion = false
    var textRegionDraft: CGRect?
    /// 文字を読み取っている間・読み取ったあとの見た目
    var textScanOverlay: TextScanOverlay?
    /// 読み取った文字を見せている吹き出し
    var textResultPopover: RecognizedTextPopover?

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
    /// 入力中の文字が変わったこと（全角の変換中も含む）を知る
    var textStorageObserver: Any?
    /// 入力中の文字を折り返す幅（画像のポイント）。画像の右端まで届かないうちは nil
    var textWrapWidth: CGFloat?
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
    private let hud = HUDView(frame: .zero)
    var selectionBar: NSView?

    // 画像の外に出す部品のウィンドウ（PinCanvasView+Outside.swift）。操作バーはいつも外（下）に出す
    var outsideClose: PinAccessory?
    var outsideQuickBar: PinAccessory?
    var outsideHUD: PinAccessory?
    var outsideHUDView: HUDView?
    var outsideSelectionBar: PinAccessory?

    init(image: CGImage, imageSize: CGSize, state: EditorState) {
        self.baseImage = image
        self.imageSize = imageSize
        self.state = state
        self.baseNSImage = NSImage(cgImage: image, size: imageSize)
        self.document = AnnotationDocument(imageSize: imageSize)
        super.init(frame: NSRect(origin: .zero, size: imageSize))

        addSubview(hud)
        updateChrome()
    }

    /// 選んだ書き込みの上に、複製・前面・背面・削除のバーを出す（動かしている間・文字の入力中は隠す）
    func updateSelectionBar() {
        let shouldShow = state.isEditing && !selection.isEmpty && moveStart == nil && handleDrag == nil && textField == nil
        guard shouldShow else {
            selectionBar?.isHidden = true
            outsideSelectionBar?.hide()
            return
        }
        if selectionBar == nil {
            let bar = makeSelectionActionBar()
            addSubview(bar, positioned: .below, relativeTo: hud)
            selectionBar = bar
        }
        guard let bar = selectionBar else { return }
        if bounds.width < bar.frame.width + 8 || bounds.height < bar.frame.height + 8 {
            // 画像の中に入らないときは、画像の上に出す（編集中はツールバーが下に出るので、上にする）
            bar.isHidden = true
            showOutsideSelectionBar()
            return
        }
        outsideSelectionBar?.hide()
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

    /// ビューの座標 → 画像の座標（表示している範囲の中に収める）
    func imagePoint(_ viewPoint: NSPoint) -> CGPoint {
        let x = viewPoint.x / scaleFactor + cropRect.minX
        let y = viewPoint.y / scaleFactor + cropRect.minY
        return CGPoint(
            x: min(max(x, cropRect.minX), cropRect.maxX),
            y: min(max(y, cropRect.minY), cropRect.maxY)
        )
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

    // MARK: - 見た目（閉じるボタン・枠・HUD）

    /// 閉じるボタン・操作バーの表示を、設定・マウスの位置・編集中かどうかに合わせる
    func updateChrome() {
        // マウスを乗せたときだけ出す設定では、画像の外に出した部品の上にマウスがあるときも「乗せている」とみなす
        let hovering = isHovering || isHoveringOutsideParts
        let visible: Bool = switch settings.closeButtonMode {
        case .always: true
        case .hover: hovering
        case .hidden: false
        }
        let editing = state.isEditing
        let clickThrough = controller?.isClickThrough ?? false
        // 画像の外の部品は、マウスを乗せたときだけ出す設定では、画像から部品へマウスを動かす間に消えないよう、少し待って隠す
        let hideDelay: TimeInterval = settings.closeButtonMode == .hover ? 0.6 : 0

        // 閉じるボタン（×）：画像を隠さないよう、編集中かどうかに関係なく、画像の左上の外側に出す
        updateOutsideClose(visible: visible && !clickThrough, hideDelay: hideDelay)

        // 操作バー：画像を隠さないよう、どんな大きさの画像でも画像の外（下。下に余白がなければ画面のいちばん下）に出す
        let showsBar = settings.showsQuickActions && visible && !editing
        updateOutsideQuickBar(visible: showsBar && !clickThrough, hideDelay: hideDelay)
        updateSelectionBar()
        needsDisplay = true
    }

    /// 拡大率・不透明度・「コピーしました」などを出す（画像の中に入らないときは、画像の上に出す）
    func showHUD(_ text: String, progress: Double? = nil) {
        let size = HUDView.size(for: text, progress: progress)
        if bounds.width >= size.width + 8, bounds.height >= size.height + 8 {
            hud.show(text, progress: progress, in: self)
        } else {
            showOutsideHUD(text, progress: progress, size: size)
        }
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

        if let draft = cropDraft ?? textRegionDraft {
            drawCropDraft(viewRect(draft))
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
                    drawFocusRing(viewRect(annotations[index].bounds))
                }
            }
            // 文字を入力している間も、選んだときと同じ点線で囲んで、入力中の文字だと分かるようにする
            if let field = textField {
                drawFocusRing(textRect(of: field))
            }
        } else if isHovering {
            // マウスを乗せている間は、背景と見分けやすいよう細い枠を出す
            NSColor.white.withAlphaComponent(0.6).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }
    }

    /// 選んでいる・入力している書き込みを囲む点線
    private func drawFocusRing(_ rect: NSRect) {
        let path = NSBezierPath(rect: rect.insetBy(dx: -5, dy: -5))
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    /// 入力欄の中の、文字の部分（入力欄は、左に約 2pt・右に 14pt・上下に 2pt の余白を持つ）
    private func textRect(of field: NSTextField) -> NSRect {
        let frame = field.frame
        return NSRect(
            x: frame.minX + TextFieldInsets.leading,
            y: frame.minY + TextFieldInsets.top,
            width: max(frame.width - TextFieldInsets.horizontal, 1),
            height: max(frame.height - TextFieldInsets.vertical, 1)
        )
    }

    /// トリミングする範囲・文字を読み取る範囲の外を暗くする
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

    /// 元の画像（書き込みなし）のうち、rect（画像のポイント座標）の部分。文字を読み取るときに使う
    func baseImagePixels(in rect: CGRect) -> CGImage? {
        let scale = CGFloat(baseImage.width) / max(imageSize.width, 1)
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height))
        guard !pixels.isEmpty else { return nil }
        return baseImage.cropping(to: pixels)
    }

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
