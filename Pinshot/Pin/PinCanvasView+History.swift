import AppKit

extension PinCanvasView {
    // MARK: - 元に戻す・やり直す

    func pushUndo(_ before: EditSnapshot) {
        history.record(before)
    }

    func commit(_ annotation: Annotation) {
        pushUndo(snapshot)
        annotations.append(annotation)
        historyChanged()
    }

    @discardableResult
    func deleteSelected() -> Bool {
        guard !selection.isEmpty else { return false }
        pushUndo(snapshot)
        let removed = Set(selection)
        let hadCounter = annotations.contains { removed.contains($0.id) && $0.counterNumber != nil }
        annotations.removeAll { removed.contains($0.id) }
        // 番号を消したら、残りを小さい順に 1, 2, 3… と詰める
        if hadCounter {
            let order = annotations.enumerated()
                .compactMap { item in item.element.counterNumber.map { (item.offset, $0) } }
                .sorted { $0.1 < $1.1 }
            for (rank, entry) in order.enumerated() {
                guard case .counter(_, let center, let radius, let style) = annotations[entry.0].shape else { continue }
                annotations[entry.0].shape = .counter(rank + 1, center: center, radius: radius, style: style)
            }
        }
        selection = []
        historyChanged()
        return true
    }

    func undo() {
        commitPendingText()
        guard let previous = history.undo(current: snapshot) else { return }
        apply(previous)
    }

    func redo() {
        commitPendingText()
        guard let next = history.redo(current: snapshot) else { return }
        apply(next)
    }

    private func apply(_ snapshot: EditSnapshot) {
        let oldCrop = cropRect
        annotations = snapshot.annotations
        cropRect = snapshot.cropRect
        if oldCrop != cropRect {
            controller?.cropDidChange(from: oldCrop, to: cropRect)
        }
        let existing = Set(annotations.map(\.id))
        selection = selection.filter { existing.contains($0) }
        historyChanged()
    }

    func historyChanged() {
        updateSelectionBar()
        state.canUndo = history.canUndo
        state.canRedo = history.canRedo
        state.nextCounterNumber = (annotations.compactMap(\.counterNumber).max() ?? 0) + 1
        needsDisplay = true
    }
}
