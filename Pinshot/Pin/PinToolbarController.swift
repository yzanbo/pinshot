import AppKit
import SwiftUI

/// 浮かせた画像 1 枚ぶんの、編集ツールバーのウィンドウ（出す・隠す・置く場所・説明のポップアップ）
@MainActor
final class PinToolbarController {
    private let pinPanel: PinPanel
    private let state: EditorState
    private var toolbarPanel: ToolbarPanel?

    /// つまみで動かし始めたときの、マウスと（画像かツールバーの）位置
    private var moveStartMouse: NSPoint?
    private var moveStartOrigin: NSPoint = .zero
    /// 切り離したツールバーを置いた位置（次に編集モードに入ったときも同じ場所に出す）
    private var detachedOrigin: NSPoint?
    /// この時刻までは、ツールバーの大きさが変わるたびに中央に置き直す（出した直後のため）
    private var recentreUntil = Date.distantPast
    private let hintBubble = HintBubble()
    private var hintTask: Task<Void, Never>?

    init(pinPanel: PinPanel, state: EditorState) {
        self.pinPanel = pinPanel
        self.state = state
    }

    // MARK: - 出す・隠す

    func show(actions: ToolbarActions) {
        guard toolbarPanel == nil else { return }
        let hosting = FirstMouseHostingView(rootView: EditorToolbar(state: state, actions: actions))
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

    /// 画像のウィンドウの階層が変わったら、ツールバーも合わせる（切り離しているときは一段前）
    func updateLevel() {
        toolbarPanel?.level = state.isDetached ? NSWindow.Level(rawValue: pinPanel.level.rawValue + 1) : pinPanel.level
    }

    /// 画像に付けるときは子ウィンドウ（画像と一緒に動く）、切り離すときは独立したウィンドウにする
    func applyAttachment() {
        guard let toolbar = toolbarPanel else { return }
        if state.isDetached {
            pinPanel.removeChildWindow(toolbar)
            // 画像をクリックして前に出しても、ツールバーが下に隠れないよう一段前に置く
            toolbar.level = NSWindow.Level(rawValue: pinPanel.level.rawValue + 1)
            if let origin = detachedOrigin {
                toolbar.setFrameOrigin(origin)
            } else {
                layout(force: true)
                detachedOrigin = toolbar.frame.origin
            }
            keepOnScreen()
            toolbar.orderFrontRegardless()
        } else {
            toolbar.level = pinPanel.level
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
            let x = min(max(left, visible.minX + 4), visible.maxX - size.width - 4)
            toolbar.setFrameOrigin(NSPoint(x: x, y: toolbar.frame.minY))
        }
    }

    /// ツールバーを画像の下に置く。画面からはみ出すときは上、それも無理なら画像の内側に置く
    /// （切り離しているときは動かさない。force のときだけ置き直す）
    func layout(force: Bool = false) {
        guard let toolbar = toolbarPanel, force || !state.isDetached else { return }
        let frame = pinPanel.frame
        let size = toolbar.frame.size
        let screen = ScreenGeometry.screen(containing: NSPoint(x: frame.midX, y: frame.midY), orMain: false)
            ?? pinPanel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? frame
        let gap: CGFloat = 8

        var x = frame.midX - size.width / 2
        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)

        var y = frame.minY - size.height - gap
        if y < visible.minY {
            y = frame.maxY + gap
        }
        if y + size.height > visible.maxY {
            y = max(frame.minY + gap, visible.minY + gap)
        }
        toolbar.setFrameOrigin(NSPoint(x: x, y: y))
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

    /// つまみのドラッグで動かす（最初の呼び出しでマウスと位置を覚え、そこからの差で動かす）
    func moveWithMouse() {
        let mouse = NSEvent.mouseLocation
        // 切り離しているときはツールバーだけ、付いているときは画像ごと動かす
        let target: NSWindow? = state.isDetached ? toolbarPanel : pinPanel
        guard let target else { return }
        guard let start = moveStartMouse else {
            moveStartMouse = mouse
            moveStartOrigin = target.frame.origin
            NSCursor.closedHand.set()
            // つまみの説明は、ドラッグを始めたら消す（動かしている間は出さない）
            hideHint()
            return
        }
        target.setFrameOrigin(NSPoint(x: moveStartOrigin.x + mouse.x - start.x, y: moveStartOrigin.y + mouse.y - start.y))
    }

    func endMoveWithMouse() {
        moveStartMouse = nil
        if state.isDetached {
            keepOnScreen()
        } else {
            layout()
        }
    }

    // MARK: - 説明のポップアップ

    /// ボタンの説明（初めは少し待ってから出し、出ている間はすぐ差し替える）
    func updateHint(_ hint: String?) {
        hintTask?.cancel()
        // ドラッグで動かしている間は出さない
        guard let hint, state.showsHints, moveStartMouse == nil, let toolbar = toolbarPanel, toolbar.isVisible else {
            hintBubble.hide()
            return
        }
        if hintBubble.isShown {
            hintBubble.show(hint, at: NSEvent.mouseLocation, avoiding: toolbar.frame)
            return
        }
        hintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, self.state.hoverHint == hint, self.moveStartMouse == nil, let toolbar = self.toolbarPanel else { return }
            self.hintBubble.show(hint, at: NSEvent.mouseLocation, avoiding: toolbar.frame)
        }
    }

    private func hideHint() {
        hintTask?.cancel()
        hintBubble.hide()
    }
}
