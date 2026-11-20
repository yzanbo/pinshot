import Foundation

/// 1 枚の画像の編集データ（書き込み・トリミング・元に戻す履歴）。
///
/// 書き込みとトリミングを変えるときは、必ずここのメソッドを通す。そうすることで、どこから変えても次の決まりが守られる。
/// - どの変更も「元に戻す」に 1 回ずつ積む（ドラッグや文字の直しは、終わったときにまとめて 1 回）
/// - 番号を消したら、残りを 1, 2, 3… と詰める
/// - 同じ書き込みの色などを続けて変えたときは、1 つにまとめる（元に戻す・やり直す・ほかの変更のあとは、まとめない）
struct AnnotationDocument {
    /// 書き込み（後ろほど前面）。座標は元の画像のポイント座標（左上が原点）
    private(set) var annotations: [Annotation] = []
    /// 表示している範囲（画像のポイント座標）。トリミングで小さくなる
    private(set) var cropRect: CGRect

    private var history = EditHistory()
    /// 色・大きさなどを続けて変えているときの、まとめる相手（最後に変えた書き込みと時刻）
    private var coalescing: (id: UUID, time: Date)?
    /// ドラッグ・文字の直しなど、終わったときに 1 回だけ積む変更を始めたときの状態
    private var changeStart: EditSnapshot?

    init(imageSize: CGSize) {
        cropRect = CGRect(origin: .zero, size: imageSize)
    }

    // MARK: - 読む

    var snapshot: EditSnapshot { EditSnapshot(annotations: annotations, cropRect: cropRect) }
    var canUndo: Bool { history.canUndo || changeStart.map { $0 != snapshot } == true }
    var canRedo: Bool { history.canRedo }

    /// 次に置く番号（いまある番号のいちばん大きい数 + 1）
    var nextCounterNumber: Int { (annotations.compactMap(\.counterNumber).max() ?? 0) + 1 }

    func index(of id: UUID) -> Int? {
        annotations.firstIndex { $0.id == id }
    }

    /// ids の書き込みの位置（ids の順。ないものは飛ばす）
    func indices(of ids: [UUID]) -> [Int] {
        ids.compactMap(index(of:))
    }

    // MARK: - 1 回ずつ「元に戻す」に積む変更

    mutating func add(_ annotation: Annotation) {
        record()
        annotations.append(annotation)
    }

    /// ids の書き込みを消す。番号を消したら、残りを小さい順に 1, 2, 3… と詰める。消したものがなければ false
    @discardableResult
    mutating func remove(ids: Set<UUID>) -> Bool {
        guard annotations.contains(where: { ids.contains($0.id) }) else { return false }
        record()
        let hadCounter = annotations.contains { ids.contains($0.id) && $0.counterNumber != nil }
        annotations.removeAll { ids.contains($0.id) }
        if hadCounter {
            renumberCounters()
        }
        return true
    }

    /// ids の書き込みを offset だけずらして複製し、いちばん前面に足す（重なり順は保ち、番号は続きの番号にする）。
    /// 足した書き込みの id を返す
    mutating func duplicate(ids: [UUID], offset: CGVector) -> [UUID] {
        let sources = indices(of: ids).sorted()
        guard !sources.isEmpty else { return [] }
        record()
        var nextNumber = nextCounterNumber
        var newIDs: [UUID] = []
        for index in sources {
            var copy = annotations[index].translated(by: offset)
            copy.id = UUID()
            if case .counter(_, let center, let radius, let style) = copy.shape {
                copy.shape = .counter(nextNumber, center: center, radius: radius, style: style)
                nextNumber += 1
            }
            annotations.append(copy)
            newIDs.append(copy.id)
        }
        return newIDs
    }

    /// ids の書き込みを、1 つ前面（forward）か背面へ動かす。どれも動かせなければ false
    @discardableResult
    mutating func reorder(ids: [UUID], forward: Bool) -> Bool {
        var targets = indices(of: ids).sorted()
        guard !targets.isEmpty else { return false }
        let before = snapshot
        var changed = false
        if forward {
            for index in targets.reversed() where index < annotations.count - 1 && !targets.contains(index + 1) {
                annotations.swapAt(index, index + 1)
                targets = targets.map { $0 == index ? index + 1 : $0 }
                changed = true
            }
        } else {
            for index in targets where index > 0 && !targets.contains(index - 1) {
                annotations.swapAt(index, index - 1)
                targets = targets.map { $0 == index ? index - 1 : $0 }
                changed = true
            }
        }
        guard changed else { return false }
        record(before)
        return true
    }

    /// ids の書き込みを動かす（矢印キー）
    mutating func translate(ids: [UUID], by offset: CGVector) {
        let targets = indices(of: ids)
        guard !targets.isEmpty else { return }
        record()
        for index in targets {
            annotations[index] = annotations[index].translated(by: offset)
        }
    }

    /// ids の書き込みを transform で作り直す（変わったものだけ）。何か変わったら true。
    /// 同じ書き込み（ids の先頭）を interval 秒以内に続けて変えたときは、最初の状態だけを「元に戻す」に残す
    /// （カラーパネルで色を動かし続けたときなど）
    @discardableResult
    mutating func update(
        ids: [UUID],
        coalescingWithin interval: TimeInterval = 1,
        now: Date = Date(),
        _ transform: (Annotation) -> Annotation
    ) -> Bool {
        let changes = indices(of: ids).compactMap { index -> (Int, Annotation)? in
            let updated = transform(annotations[index])
            return updated == annotations[index] ? nil : (index, updated)
        }
        guard !changes.isEmpty, let key = ids.first else { return false }
        let isContinuing = changeStart == nil
            && (coalescing.map { $0.id == key && now.timeIntervalSince($0.time) < interval } ?? false)
        if !isContinuing {
            record()
        }
        coalescing = (key, now)
        for (index, updated) in changes {
            annotations[index] = updated
        }
        return true
    }

    /// いまの範囲の中を、rect でトリミングする（小さすぎる・変わらないときはしない）。変えたら、前の範囲を返す
    mutating func crop(to rect: CGRect) -> CGRect? {
        let newCrop = rect.standardized.intersection(cropRect).integral
        guard newCrop.width >= 8, newCrop.height >= 8, newCrop != cropRect else { return nil }
        record()
        let old = cropRect
        cropRect = newCrop
        return old
    }

    /// 元に戻す。戻せたら true
    mutating func undo() -> Bool {
        endChange(keep: true)
        guard let previous = history.undo(current: snapshot) else { return false }
        set(previous)
        return true
    }

    /// やり直す。やり直せたら true
    mutating func redo() -> Bool {
        endChange(keep: true)
        guard let next = history.redo(current: snapshot) else { return false }
        set(next)
        return true
    }

    /// 閉じた画像を戻すときなど、履歴に積まずに状態を丸ごと入れる
    mutating func restore(_ snapshot: EditSnapshot) {
        changeStart = nil
        set(snapshot)
    }

    // MARK: - 終わったときに 1 回だけ積む変更（ドラッグ・文字の直し）

    /// 変更を始める（いまの状態を覚える）。前の変更が終わっていなければ、それは確定する
    mutating func beginChange() {
        endChange(keep: true)
        changeStart = snapshot
    }

    /// 変更の途中で、同じ id の書き込みを置き換える（ないときは何もしない）
    mutating func replace(_ annotation: Annotation) {
        guard let index = index(of: annotation.id) else { return }
        annotations[index] = annotation
    }

    /// 変更の途中で、書き込みを取り出す（書いた文字を直している間は、元の文字を描かないため）
    mutating func takeOut(at index: Int) -> Annotation {
        annotations.remove(at: index)
    }

    /// 変更の途中で、書き込みを入れる（位置は範囲に収める）
    mutating func insert(_ annotation: Annotation, at index: Int) {
        annotations.insert(annotation, at: min(max(index, 0), annotations.count))
    }

    /// 変更を終える。keep が true で何か変わっていれば、始める前の状態を「元に戻す」に積む。
    /// keep が false なら、始める前の状態に戻す
    mutating func endChange(keep: Bool) {
        guard let start = changeStart else { return }
        changeStart = nil
        if !keep {
            annotations = start.annotations
            cropRect = start.cropRect
        } else if start != snapshot {
            history.record(start)
            coalescing = nil
        }
    }

    // MARK: - 中で使う

    /// 変える前の状態を「元に戻す」に積む（終わっていない変更があれば、先にそれを積む）
    private mutating func record(_ before: EditSnapshot? = nil) {
        let before = before ?? snapshot
        endChange(keep: true)
        history.record(before)
        coalescing = nil
    }

    private mutating func set(_ snapshot: EditSnapshot) {
        annotations = snapshot.annotations
        cropRect = snapshot.cropRect
        coalescing = nil
    }

    /// 番号を、小さい順に 1, 2, 3… と詰める（重なり順は変えない）
    private mutating func renumberCounters() {
        let order = annotations.enumerated()
            .compactMap { item in item.element.counterNumber.map { (item.offset, $0) } }
            .sorted { $0.1 < $1.1 }
        for (rank, entry) in order.enumerated() {
            guard case .counter(_, let center, let radius, let style) = annotations[entry.0].shape else { continue }
            annotations[entry.0].shape = .counter(rank + 1, center: center, radius: radius, style: style)
        }
    }
}
