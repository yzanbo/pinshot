import Foundation

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
