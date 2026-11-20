import AppKit

/// Mac に入っているフォントから、文字・番号のフォントを選ぶメニュー
@MainActor
enum FontMenu {
    /// 標準（システムのフォント）を表す名前
    static let systemName = "標準"

    /// ツールバーに出すフォントの名前（family が nil なら「標準」）
    static func displayName(of family: String?) -> String {
        guard let family else { return systemName }
        return NSFontManager.shared.localizedName(forFamily: family, face: nil)
    }

    /// マウスの位置にメニューを開く。各項目は、そのフォントで名前を表示する
    static func popUp(current: String?, onSelect: @escaping @MainActor (String?) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let system = ClosureMenuItem(title: "\(systemName)（システムのフォント）") { onSelect(nil) }
        system.state = current == nil ? .on : .off
        menu.addItem(system)
        menu.addItem(.separator())

        let manager = NSFontManager.shared
        // 「.」で始まるのは、システムが内部で使うフォント
        let families = manager.availableFontFamilies.filter { !$0.hasPrefix(".") }
        let named = families
            .map { (family: $0, name: manager.localizedName(forFamily: $0, face: nil)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for entry in named {
            let item = ClosureMenuItem(title: entry.name) { onSelect(entry.family) }
            if let font = manager.font(withFamily: entry.family, traits: [], weight: 5, size: 13) {
                item.attributedTitle = NSAttributedString(string: entry.name, attributes: [.font: font])
            }
            item.state = entry.family == current ? .on : .off
            menu.addItem(item)
        }
        // いま選んでいるフォントがすぐ見えるよう、その項目がマウスの位置に来るように開く
        let selected = menu.items.first { $0.state == .on }
        let mouse = NSEvent.mouseLocation
        menu.popUp(positioning: selected, at: NSPoint(x: mouse.x - 10, y: mouse.y - 8), in: nil)
    }
}
