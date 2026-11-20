import AppKit

/// 部品（閉じるボタン・操作バー・お知らせ・書き込みのバー）を、画像の外に出すウィンドウ（閉じるボタンと操作バーはいつも、ほかは画像が小さくて中に入らないとき）。
/// 画像のウィンドウの子ウィンドウにして、画像と一緒に動かす。置き場所は部品ごとに決まっていて、画面の端では反対側に回す
@MainActor
final class PinAccessory {
    enum Placement {
        /// 画像の下（画面に見えている部分の左右の真ん中）。画像の下に余白がなければ、画面のいちばん下（画像に重ねる）
        case below
        /// 画像の上（左右の真ん中）。入らなければ下
        case above
        /// 画像の左上の角の外側（斜め左上）。画面の端で入らなければ、反対側・内側寄りに回す
        case topLeftOutside
    }

    private let panel: OverlayPanel
    private let container: HoverTrackingView
    private weak var parent: NSWindow?
    private let placement: Placement
    private let gap: CGFloat
    private var hideTask: Task<Void, Never>?

    /// マウスを乗せた・離したとき（マウスを乗せたときだけ出す設定で、出し続けるかを決め直すのに使う）
    var onHoverChange: (() -> Void)? {
        get { container.onHoverChange }
        set { container.onHoverChange = newValue }
    }

    /// マウスがこの部品の上にあるか
    var isHovering: Bool { container.isHovering }
    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    /// passesClicks: クリックを受けない（お知らせなど）
    init(parent: NSWindow, placement: Placement, gap: CGFloat = 6, content: NSView, passesClicks: Bool = false) {
        self.parent = parent
        self.placement = placement
        self.gap = gap
        container = HoverTrackingView(frame: NSRect(origin: .zero, size: content.frame.size))
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        panel = OverlayPanel(contentRect: container.frame, level: parent.level, hasShadow: false)
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = passesClicks
        panel.contentView = container
    }

    /// 中身の大きさを変える
    func setContentSize(_ size: NSSize) {
        guard panel.frame.size != size else { return }
        panel.setContentSize(size)
        if panel.isVisible, let parent { place(around: parent.frame) }
    }

    /// 出す。anchor（スクリーン座標）を渡すと、画像の代わりにその四角のまわりに置く
    func show(around anchor: NSRect? = nil) {
        hideTask?.cancel()
        hideTask = nil
        guard let parent else { return }
        place(around: anchor ?? parent.frame)
        panel.level = parent.level
        if panel.parent == nil {
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    /// 出すか隠すかを決める。hideDelay があれば少し待ってから隠す（画像から部品へマウスを動かす間に消えないように）
    func update(visible: Bool, hideDelay: TimeInterval = 0) {
        if visible {
            show()
            return
        }
        guard panel.isVisible else { return }
        guard hideDelay > 0 else {
            hide()
            return
        }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hideDelay))
            guard let self, !Task.isCancelled, !self.isHovering else { return }
            self.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// 出しているときに、画像のいまの位置に合わせて置き直す（画像を動かした・大きさを変えたとき）
    func reposition() {
        guard panel.isVisible, let parent else { return }
        place(around: parent.frame)
    }

    private func place(around frame: NSRect) {
        let size = panel.frame.size
        let visible = ScreenGeometry.screen(intersecting: frame)?.visibleFrame ?? frame
        var origin: NSPoint
        switch placement {
        case .below:
            // 画像の下に余白がなければ、上へは回さず、画面のいちばん下に出す（編集のツールバーと同じ決まり）
            origin = ScreenGeometry.originBelow(frame, size: size, gap: gap, in: visible)
        case .above:
            origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY + gap)
            if origin.y + size.height > visible.maxY { origin.y = frame.minY - gap - size.height }
        case .topLeftOutside:
            // 丸いボタンの縁が、画像の角にちょうど触れるところに置く（四角い枠の角どうしを合わせるより、√2 倍ぶん寄せる）
            let diagonal = gap - size.width / 2 * (1 - 1 / 2.squareRoot())
            origin = NSPoint(x: frame.minX - diagonal - size.width, y: frame.maxY + diagonal)
            // 左に入らなければ右上の外側
            if origin.x < visible.minX { origin.x = frame.maxX + diagonal }
            // 上に入らなければ角の横（上の端にそろえる）。このときは画像に重ならないよう、少し離す
            if origin.y + size.height > visible.maxY {
                origin.y = frame.maxY - size.height
                origin.x = origin.x < frame.minX ? frame.minX - gap - size.width : frame.maxX + gap
            }
        }
        if placement != .topLeftOutside {
            // 左右は画面の中に収める
            origin.x = ScreenGeometry.clampedX(origin.x, width: size.width, in: visible)
        }
        panel.setFrameOrigin(NSPoint(x: origin.x.rounded(), y: origin.y.rounded()))
    }
}

/// 中身を包んで、マウスが乗っているかを知らせるビュー
private final class HoverTrackingView: NSView {
    var onHoverChange: (() -> Void)?
    private(set) var isHovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        resetTrackingArea([.mouseEnteredAndExited])
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverChange?()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChange?()
    }
}
