import AppKit

/// メニューの項目（押したときの処理を、その場に書ける）
enum MenuEntry {
    /// key はメニューに出すショートカット（"c" なら ⌘C）
    case item(
        title: String,
        image: NSImage? = nil,
        isChecked: Bool = false,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        action: @MainActor () -> Void
    )
    case submenu(title: String, entries: [MenuEntry])
    case disabled(title: String)
    case separator
}

/// MenuEntry の並びから NSMenu を作る・開く。
/// ツールバーのメニューは、SwiftUI の Menu の余白に左右されないよう、これで自前で開く
@MainActor
enum PopupMenu {
    /// マウスの位置に開く
    static func popUp(_ entries: [MenuEntry]) {
        let menu = makeMenu(entries)
        let mouse = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: mouse.x - 10, y: mouse.y - 8), in: nil)
    }

    static func makeMenu(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .item(title, image, isChecked, key, modifiers, action):
                let item = ClosureMenuItem(title: title, key: key, modifiers: modifiers, handler: action)
                item.image = image
                item.state = isChecked ? .on : .off
                menu.addItem(item)
            case let .submenu(title, children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = makeMenu(children)
                menu.addItem(item)
            case let .disabled(title):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        return menu
    }
}

/// 押したときに、渡した処理を呼ぶメニュー項目
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(
        title: String,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        handler: @escaping @MainActor () -> Void
    ) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() {
        // メニューの項目はメインスレッドで押される
        MainActor.assumeIsolated { handler() }
    }
}
