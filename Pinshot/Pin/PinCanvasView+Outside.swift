import AppKit

/// 部品を画像の外に出す（操作バーはいつも。単独の捨てるボタン・お知らせ・書き込みのバーは、画像が小さくて中に入らないとき）。
/// 置き場所は部品ごとに決まっている（単独の捨てるボタンは左、操作バーは下、お知らせと書き込みのバーは上）
extension PinCanvasView {
    // MARK: - 判定

    /// 画像の外に出した部品（捨てるボタンと操作バー）の上に、マウスがあるか
    var isHoveringOutsideParts: Bool {
        (outsideClose?.isHovering ?? false) || (outsideQuickBar?.isHovering ?? false)
    }

    // MARK: - 単独の捨てるボタン（画像の左。操作バーを出さない設定のとき）

    func updateOutsideClose(visible: Bool, hideDelay: TimeInterval) {
        if visible, outsideClose == nil, let window {
            let button = PinCloseButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
            button.onClick = { [weak self] in self?.controller?.close() }
            let accessory = PinAccessory(parent: window, placement: .left, gap: 4, content: button)
            accessory.onHoverChange = { [weak self] in self?.updateChrome() }
            outsideClose = accessory
        }
        outsideClose?.update(visible: visible, hideDelay: hideDelay)
    }

    // MARK: - 操作バー（いつも画像の下）

    func updateOutsideQuickBar(visible: Bool, hideDelay: TimeInterval) {
        if visible, outsideQuickBar == nil, let window, let controller {
            let bar = FirstMouseHostingView(rootView: makeQuickActionBar(appearance: controller.appearance))
            bar.frame.size = bar.fittingSize
            let accessory = PinAccessory(parent: window, placement: .below, content: bar)
            accessory.onHoverChange = { [weak self] in self?.updateChrome() }
            outsideQuickBar = accessory
        }
        outsideQuickBar?.update(visible: visible, hideDelay: hideDelay)
    }

    // MARK: - お知らせ（画像の上）

    func showOutsideHUD(_ text: String, progress: Double?, size: NSSize) {
        guard let window else { return }
        if outsideHUD == nil {
            let hud = HUDView(frame: NSRect(origin: .zero, size: size))
            let accessory = PinAccessory(parent: window, placement: .above, content: hud, passesClicks: true)
            hud.onFadeOut = { [weak accessory] in accessory?.hide() }
            outsideHUD = accessory
            outsideHUDView = hud
        }
        guard let accessory = outsideHUD, let hud = outsideHUDView, let container = hud.superview else { return }
        accessory.setContentSize(size)
        // 書き込みのバーを画像の上に出しているときは、そのさらに上に出す（重ならないように）
        var anchor = window.frame
        if let bar = outsideSelectionBar, bar.isVisible {
            anchor = anchor.union(bar.frame)
        }
        accessory.show(around: anchor)
        hud.show(text, progress: progress, in: container)
    }

    // MARK: - 書き込みのバー（画像の上）

    func showOutsideSelectionBar() {
        guard let window else { return }
        if outsideSelectionBar == nil {
            let bar = FirstMouseHostingView(rootView: SelectionActionBar(
                duplicate: { [weak self] in self?.duplicateSelected() },
                bringForward: { [weak self] in self?.reorderSelected(forward: true) },
                sendBackward: { [weak self] in self?.reorderSelected(forward: false) },
                delete: { [weak self] in self?.deleteSelected() }
            ))
            bar.frame.size = bar.fittingSize
            outsideSelectionBar = PinAccessory(parent: window, placement: .above, content: bar)
        }
        outsideSelectionBar?.show()
    }

    // MARK: - 置き直し

    /// 画像を動かした・大きさを変えたとき、外に出している操作バーと捨てるボタンを置き直す
    /// （子ウィンドウは画像と一緒に動くだけなので、画面の下端に掛かったら画面のいちばん下へ移す）
    func repositionOutsideParts() {
        outsideQuickBar?.reposition()
        outsideClose?.reposition()
    }

    // MARK: - 片付け

    /// 画像の外に出している部品をすべて隠す（画像を閉じるとき）
    func hideOutsideParts() {
        outsideClose?.hide()
        outsideQuickBar?.hide()
        outsideHUD?.hide()
        outsideSelectionBar?.hide()
    }
}
