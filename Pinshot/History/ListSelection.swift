import AppKit

/// 一覧で選んでいるもの（クリック・⌘ + クリック・shift + クリック・⌘A・矢印キー）。
/// 画像の履歴と文字の履歴で同じ選び方にするため、ここにまとめる（テストで確かめる）。order は一覧に並んでいる順の id
struct ListSelection: Equatable {
    private(set) var selected: Set<UUID> = []
    /// shift + クリックで範囲を選ぶときの、起点
    private(set) var anchor: UUID?

    var isEmpty: Bool { selected.isEmpty }
    func contains(_ id: UUID) -> Bool { selected.contains(id) }

    /// クリックで選ぶ（command で足す・外す、shift で起点からの範囲。両方なら範囲を足す）
    mutating func click(_ id: UUID, command: Bool, shift: Bool, order: [UUID]) {
        if shift, let anchor, let range = Self.range(from: anchor, to: id, in: order) {
            selected = command ? selected.union(range) : range
            return
        }
        if command {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        } else {
            selected = [id]
        }
        anchor = id
    }

    mutating func selectAll(_ order: [UUID]) {
        selected = Set(order)
    }

    mutating func clear() {
        selected = []
        anchor = nil
    }

    /// となりを選ぶ（step は +1 で次、-1 で前。extending なら範囲を広げる）
    mutating func move(by step: Int, extending: Bool, order: [UUID]) {
        guard !order.isEmpty else { return }
        let current = anchor.flatMap { order.firstIndex(of: $0) }
        let next = current.map { min(max($0 + step, 0), order.count - 1) } ?? (step > 0 ? 0 : order.count - 1)
        if extending, let start = current {
            selected.formUnion(order[min(start, next)...max(start, next)])
        } else {
            selected = [order[next]]
        }
        anchor = order[next]
    }

    /// 消したものを、選んでいるものから外す
    mutating func remove(_ ids: Set<UUID>) {
        selected.subtract(ids)
        if let anchor, ids.contains(anchor) { self.anchor = nil }
    }

    private static func range(from start: UUID, to end: UUID, in order: [UUID]) -> Set<UUID>? {
        guard let a = order.firstIndex(of: start), let b = order.firstIndex(of: end) else { return nil }
        return Set(order[min(a, b)...max(a, b)])
    }
}

/// 一覧のキー操作でしたいこと。どのキーで何をするかは ListKeys が決め、実行は一覧ごとに行う
enum ListKeyAction: Equatable {
    /// ⌘A：すべて選ぶ
    case selectAll
    /// 矢印：となりを選ぶ（shift で範囲を広げる）
    case move(by: Int, extending: Bool)
    /// esc：選ぶのをやめる
    case clearSelection
    /// delete：選んでいるものを消す
    case remove
    /// return：選んでいるものを使う（画像は浮かせる・文字はコピー・共有はブラウザで開く）
    case activate
    /// ⌘C：選んでいるものをコピーする
    case copy
}

/// 一覧のキー操作の決まり（画像・文字・共有の一覧で同じにする。テストで確かめる）
enum ListKeys {
    /// キーで一覧ですること（扱わないキーなら nil。一覧に任せずに、ほかへ流す）。
    /// key は修飾キーなしの文字（charactersIgnoringModifiers）。
    /// horizontal: ← → で動かす（サムネイル・リスト）。vertical: ↑ ↓ で動かす（リスト・文字の一覧。
    /// サムネイルでは扱わず、一覧のスクロールに任せる）
    static func action(
        keyCode: UInt16,
        key: String?,
        modifiers: NSEvent.ModifierFlags,
        horizontal: Bool,
        vertical: Bool
    ) -> ListKeyAction? {
        let flags = modifiers.intersection([.command, .option, .control, .shift])
        let extending = flags.contains(.shift)
        switch keyCode {
        case KeyCode.leftArrow, KeyCode.rightArrow:
            return horizontal ? .move(by: keyCode == KeyCode.rightArrow ? 1 : -1, extending: extending) : nil
        case KeyCode.downArrow, KeyCode.upArrow:
            return vertical ? .move(by: keyCode == KeyCode.downArrow ? 1 : -1, extending: extending) : nil
        case KeyCode.escape:
            return .clearSelection
        case KeyCode.delete, KeyCode.forwardDelete:
            return .remove
        case KeyCode.return, KeyCode.keypadEnter:
            return .activate
        default:
            guard flags == .command else { return nil }
            switch key?.lowercased() {
            case "a": return .selectAll
            case "c": return .copy
            default: return nil
            }
        }
    }

    /// event で一覧ですること
    static func action(for event: NSEvent, horizontal: Bool, vertical: Bool) -> ListKeyAction? {
        action(keyCode: event.keyCode, key: event.charactersIgnoringModifiers, modifiers: event.modifierFlags, horizontal: horizontal, vertical: vertical)
    }
}
