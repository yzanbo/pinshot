import AppKit

extension PinCanvasView {
    // MARK: - 元に戻す・やり直す

    /// 書き込みを 1 つ足す
    func commit(_ annotation: Annotation) {
        document.add(annotation)
        historyChanged()
    }

    @discardableResult
    func deleteSelected() -> Bool {
        guard document.remove(ids: Set(selection)) else { return false }
        selection = []
        historyChanged()
        return true
    }

    func undo() {
        commitPendingText()
        let oldCrop = cropRect
        guard document.undo() else { return }
        historyJumped(from: oldCrop)
    }

    func redo() {
        commitPendingText()
        let oldCrop = cropRect
        guard document.redo() else { return }
        historyJumped(from: oldCrop)
    }

    /// 元に戻す・やり直すで状態が変わったあと、ウィンドウの大きさ（トリミング）と選択を合わせる
    private func historyJumped(from oldCrop: CGRect) {
        if oldCrop != cropRect {
            controller?.cropDidChange(from: oldCrop, to: cropRect)
        }
        let existing = Set(annotations.map(\.id))
        selection = selection.filter { existing.contains($0) }
        historyChanged()
    }

    /// 書き込み・履歴が変わったら、ツールバー（元に戻すボタン・次の番号）と表示を合わせる
    func historyChanged() {
        updateSelectionBar()
        state.canUndo = document.canUndo
        state.canRedo = document.canRedo
        state.nextCounterNumber = document.nextCounterNumber
        needsDisplay = true
    }
}
