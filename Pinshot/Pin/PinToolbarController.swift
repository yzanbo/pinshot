import AppKit
import SwiftUI

/// 浮かせた画像 1 枚ぶんの、編集ツールバーのウィンドウ（出す・隠す・置く場所・説明のポップアップ）
@MainActor
final class PinToolbarController {
    private let pinPanel: PinPanel
    private let state: EditorState
    private var toolbarPanel: ToolbarPanel?

    /// つまみで動かし始めたときの、マウスと（画像かツールバーの）位置と、動かしているウィンドウ
    private var moveStartMouse: NSPoint?
    private var moveStartOrigin: NSPoint = .zero
    private weak var moveTarget: NSWindow?
    /// 切り離したツールバーを置いた位置（次に編集モードに入ったときも同じ場所に出す）
    private var detachedOrigin: NSPoint?
    /// この時刻までは、ツールバーの大きさが変わるたびに中央に置き直す（出した直後のため）
    private var recentreUntil = Date.distantPast
    /// いま出している説明（ほかのボタンに乗り移ったときに、そちらの説明を消さないよう覚える）
    private var shownHint: String?

    init(pinPanel: PinPanel, state: EditorState) {
        self.pinPanel = pinPanel
        self.state = state
    }

    // MARK: - 出す・隠す

    func show(actions: ToolbarActions, appearance: PinAppearance) {
        guard toolbarPanel == nil else { return }
        let hosting = FirstMouseHostingView(rootView: EditorToolbar(state: state, appearance: appearance, actions: actions))
        let size = hosting.fittingSize
        let toolbar = ToolbarPanel(contentRect: NSRect(origin: .zero, size: size))
        toolbar.level = pinPanel.level
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        toolbar.contentView = hosting
        toolbarPanel = toolbar
        applyAttachment()
        // 出した直後は 1 行目の幅を測り終えていないことがあるので、しばらくは大きさが変わるたびに中央に置き直す
        recentreUntil = Date().addingTimeInterval(0.6)
        for delay in [0.0, 0.05, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.fitSize(recentre: true)
            }
        }
    }

    func hide() {
        hideHint()
        // つまみのドラッグ中に隠したとき（esc で編集を終えたなど）に、ドラッグの途中の状態が残らないようにする
        moveStartMouse = nil
        guard let toolbar = toolbarPanel else { return }
        pinPanel.removeChildWindow(toolbar)
        toolbar.orderOut(nil)
        toolbarPanel = nil
    }

    /// 画像のウィンドウの階層が変わったら、ツールバーも合わせる。
    /// 切り離しているときは、画像をクリックして前に出してもツールバーが下に隠れないよう、一段前に置く
    func updateLevel() {
        toolbarPanel?.level = state.isDetached ? NSWindow.Level(rawValue: pinPanel.level.rawValue + 1) : pinPanel.level
    }

    /// 画像に付けるときは子ウィンドウ（画像と一緒に動く）、切り離すときは独立したウィンドウにする
    func applyAttachment() {
        guard let toolbar = toolbarPanel else { return }
        if state.isDetached {
            pinPanel.removeChildWindow(toolbar)
            updateLevel()
            if let origin = detachedOrigin {
                toolbar.setFrameOrigin(origin)
            } else {
                layout(force: true)
                detachedOrigin = toolbar.frame.origin
            }
            keepOnScreen()
            toolbar.orderFrontRegardless()
        } else {
            updateLevel()
            if toolbar.parent == nil {
                pinPanel.addChildWindow(toolbar, ordered: .above)
            }
            layout()
        }
    }

    // MARK: - 大きさと位置

    /// 中身の大きさに合わせる。ふだんは左端を動かさない（押そうとしたボタンが逃げないように）。
    /// recentre のとき・出した直後は、画像の下の中央に置き直す
    func fitSize(recentre requested: Bool = false) {
        guard let toolbar = toolbarPanel, let hosting = toolbar.contentView else { return }
        let recentre = requested || Date() < recentreUntil
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard size != toolbar.frame.size || recentre else { return }
        if state.isDetached {
            // 切り離しているときは、左上の位置を変えずに大きさだけ変える
            let top = toolbar.frame.maxY
            toolbar.setContentSize(size)
            toolbar.setFrameOrigin(NSPoint(x: toolbar.frame.minX, y: top - size.height))
            keepOnScreen()
        } else if recentre {
            toolbar.setContentSize(size)
            layout()
        } else {
            let left = toolbar.frame.minX
            toolbar.setContentSize(size)
            layout()
            let visible = ScreenGeometry.screen(intersecting: toolbar.frame)?.visibleFrame ?? toolbar.frame
            let x = ScreenGeometry.clampedX(left, width: size.width, in: visible)
            toolbar.setFrameOrigin(NSPoint(x: x, y: toolbar.frame.minY))
        }
    }

    /// ツールバーをいつも画像の下に置く。画像の下に余白がないとき（ドラッグで下へ動かした・拡大したなど）は、
    /// 上へは回さず、画面のいちばん下に出す（画像に重ねる）。左右は、画像のうち画面に見えている部分の真ん中
    /// （切り離しているときは動かさない。force のときだけ置き直す）
    func layout(force: Bool = false) {
        guard let toolbar = toolbarPanel, force || !state.isDetached else { return }
        let frame = pinPanel.frame
        let size = toolbar.frame.size
        let screen = ScreenGeometry.screen(containing: NSPoint(x: frame.midX, y: frame.midY), orMain: false)
            ?? pinPanel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? frame
        toolbar.setFrameOrigin(ScreenGeometry.originBelow(frame, size: size, gap: 6, in: visible))
    }

    private func keepOnScreen() {
        guard let toolbar = toolbarPanel else { return }
        let frame = toolbar.frame
        guard let visible = ScreenGeometry.screen(intersecting: frame)?.visibleFrame else { return }
        let x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        toolbar.setFrameOrigin(NSPoint(x: x, y: y))
        if state.isDetached { detachedOrigin = toolbar.frame.origin }
    }

    // MARK: - つまみで動かす

    /// つまみで動かしている最中か
    var isMovingWithHandle: Bool { moveStartMouse != nil }

    /// つまみのドラッグで動かす（最初の呼び出しでマウスと位置を覚え、そこからの差で動かす）。
    /// 編集中でツールバーを切り離しているときはツールバーだけ、そのほか（編集していないときも）は画像ごと動かす
    func moveWithMouse() {
        // 動かしている間は、マウスが画像の上に乗っても、つかんだ手のカーソルのままにする
        // （つまみから外れると矢印に、画像の上では描くツールの十字に変わってしまうため、動くたびに出し直す）
        HoverRole.movable.draggingCursor.set()
        let mouse = NSEvent.mouseLocation
        guard let start = moveStartMouse, let target = moveTarget else {
            // 切り離しているツールバーを出しているときはツールバーだけ、そうでなければ画像ごと動かす
            let target: NSWindow = state.isEditing && state.isDetached ? (toolbarPanel ?? pinPanel) : pinPanel
            moveStartMouse = mouse
            moveStartOrigin = target.frame.origin
            moveTarget = target
            // つまみの説明は、ドラッグを始めたら消す（動かしている間は出さない）
            hideHint()
            return
        }
        target.setFrameOrigin(NSPoint(x: moveStartOrigin.x + mouse.x - start.x, y: moveStartOrigin.y + mouse.y - start.y))
    }

    func endMoveWithMouse() {
        let movedToolbar = moveTarget != nil && moveTarget === toolbarPanel
        moveStartMouse = nil
        moveTarget = nil
        if movedToolbar {
            keepOnScreen()
        } else {
            layout()
        }
    }

    // MARK: - 説明のポップアップ

    /// ボタンの説明（初めは少し待ってから出し、出ている間はすぐ差し替える）
    func updateHint(_ hint: String?) {
        // ドラッグで動かしている間は出さない
        guard let hint, state.showsHints, moveStartMouse == nil, let toolbar = toolbarPanel, toolbar.isVisible else {
            hideHint()
            return
        }
        shownHint = hint
        HoverHints.shared.show(hint) { [weak self] in
            guard let self, self.moveStartMouse == nil, let toolbar = self.toolbarPanel, toolbar.isVisible else { return nil }
            return toolbar.frame
        }
    }

    private func hideHint() {
        HoverHints.shared.end(shownHint)
        shownHint = nil
    }
}
