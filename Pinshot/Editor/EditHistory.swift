import Foundation

/// 元に戻す・やり直すときに保存する、編集の状態
struct EditSnapshot: Equatable {
    var annotations: [Annotation]
    /// 表示している範囲（画像のポイント座標）。トリミングで小さくなる
    var cropRect: CGRect
}

/// 元に戻す・やり直すための履歴
struct EditHistory {
    private var undoStack: [EditSnapshot] = []
    private var redoStack: [EditSnapshot] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// 変える前の状態を積む（新しく変えたので、やり直しは捨てる）
    mutating func record(_ before: EditSnapshot) {
        undoStack.append(before)
        redoStack.removeAll()
    }

    /// 1 つ前の状態を返す。current（いまの状態）は、やり直し用に取っておく
    mutating func undo(current: EditSnapshot) -> EditSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// 元に戻す前の状態を返す。current（いまの状態）は、元に戻す用に取っておく
    mutating func redo(current: EditSnapshot) -> EditSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
