import AppKit

/// メニューバーのアイコンと、押したときのメニュー
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    /// メニューから頼む操作
    struct Actions {
        var perform: (ShortcutAction) -> Void
        /// 何秒後に撮るか
        var captureWithTimer: (Int) -> Void
        var captureWindow: (CGWindowID) -> Void
    }

    private let actions: Actions
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var windowListMenu: NSMenu?
    /// ショートカットを表示するメニュー項目（操作ごと）と、そのもとの名前
    private var actionItems: [ShortcutAction: NSMenuItem] = [:]
    private var actionTitles: [ShortcutAction: String] = [:]
    /// 画面収録の許可がないときだけ出す項目（知らせと区切り線）
    private var permissionItems: [NSMenuItem] = []
    private var pinsHeaderItem: NSMenuItem?
    private var clickThroughItem: NSMenuItem?
    /// 「撮った画像の履歴…」の項目（この上に、最近撮った画像を並べる）と、並べた項目
    private var historyItem: NSMenuItem?
    private var historyHeaderItem: NSMenuItem?
    private var recentHistoryItems: [NSMenuItem] = []
    /// メニューに並べる、最近撮った画像の数
    private let recentHistoryCount = 5

    init(actions: Actions) {
        self.actions = actions
    }

    // MARK: - メニューを作る

    /// メニューバーにアイコンを出し、メニューを付ける
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Pinshot")
        item.button?.toolTip = "Pinshot"

        let menu = NSMenu()
        menu.delegate = self

        // 画面収録の許可がないときだけ、いちばん上で知らせる（メニューを開くたびに確かめる）
        let warning = makeItem("画面収録の許可が必要です…", symbol: "exclamationmark.triangle.fill", action: #selector(openWelcome))
        warning.image = warning.image?.withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
        let warningSeparator = NSMenuItem.separator()
        menu.addItem(warning)
        menu.addItem(warningSeparator)
        permissionItems = [warning, warningSeparator]

        // キャプチャ
        menu.addItem(.sectionHeader(title: "キャプチャ"))
        for action in ShortcutAction.captureActions where action != .captureTimer {
            addActionItem(action, to: menu)
        }

        // タイマー付き（5 秒のものは、ショートカットを割り当てられる）
        let timerItem = makeItem("タイマーでキャプチャ", symbol: ShortcutAction.captureTimer.symbolName, action: nil)
        let timerMenu = NSMenu()
        for seconds in CaptureOptions.timerChoices where seconds > 0 {
            let item = NSMenuItem(title: "\(seconds) 秒後", action: #selector(captureWithTimer(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            timerMenu.addItem(item)
            if seconds == CaptureOptions.shortcutTimerSeconds {
                actionItems[.captureTimer] = item
                actionTitles[.captureTimer] = item.title
            }
        }
        timerItem.submenu = timerMenu
        menu.addItem(timerItem)

        // 開いているウィンドウの一覧から選ぶ（メニューを開くたびに作り直す）
        let windowListItem = makeItem("ウィンドウを選んでキャプチャ", symbol: "macwindow.on.rectangle", action: nil)
        let windowList = NSMenu()
        windowList.delegate = self
        windowListItem.submenu = windowList
        menu.addItem(windowListItem)
        windowListMenu = windowList

        // 撮った画像の履歴（最近撮った画像は、メニューを開くたびに並べ直す）
        menu.addItem(.separator())
        let historyHeader = NSMenuItem.sectionHeader(title: "撮った画像の履歴")
        menu.addItem(historyHeader)
        historyHeaderItem = historyHeader
        for action in ShortcutAction.historyActions {
            addActionItem(action, to: menu)
        }
        historyItem = actionItems[.openHistory]

        // 浮かせた画像
        menu.addItem(.separator())
        let pinsHeader = NSMenuItem.sectionHeader(title: "浮かせた画像")
        menu.addItem(pinsHeader)
        pinsHeaderItem = pinsHeader
        for action in ShortcutAction.pinActions {
            addActionItem(action, to: menu)
        }
        // クリックを透過している画像があるときだけ出す
        let clickThrough = makeItem("クリック透過をすべて解除", symbol: "cursorarrow.rays", action: #selector(releaseClickThrough))
        menu.addItem(clickThrough)
        clickThroughItem = clickThrough

        // アプリ
        menu.addItem(.separator())
        let settingsItem = makeItem("設定…", symbol: "gearshape", action: #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(makeItem("使い方と許可…", symbol: "questionmark.circle", action: #selector(openWelcome)))
        menu.addItem(makeItem("Pinshot について", symbol: "info.circle", action: #selector(openAbout)))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Pinshot を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        statusMenu = menu
        updateStatusMenu()
    }

    private func addActionItem(_ action: ShortcutAction, to menu: NSMenu) {
        let item = makeItem(action.label, symbol: action.symbolName, action: #selector(performActionItem(_:)))
        item.representedObject = action.rawValue
        menu.addItem(item)
        actionItems[action] = item
        actionTitles[action] = action.label
    }

    private func makeItem(_ title: String, symbol: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = action == nil ? nil : self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    /// メニューを開くたびに、いまの状態（許可・浮かせている画像の数・クリック透過）に合わせる
    private func updateStatusMenu() {
        let needsPermission = !ScreenPermission.isGranted
        permissionItems.forEach { $0.isHidden = !needsPermission }

        let pins = PinManager.shared
        pinsHeaderItem?.title = pins.pinCount > 0 ? "浮かせた画像（\(pins.pinCount) 枚）" : "浮かせた画像"
        clickThroughItem?.isHidden = !pins.hasClickThroughPins
        updateRecentHistory()
    }

    /// 「撮った画像の履歴…」の上に、最近撮った画像を縮小画像付きで並べる。
    /// 押すと浮かせる。⌥ を押している間は「コピー」に変わる。履歴がないときは、その旨を出す
    private func updateRecentHistory() {
        guard let menu = statusMenu, let historyItem else { return }
        recentHistoryItems.forEach { menu.removeItem($0) }
        recentHistoryItems = []
        let history = CaptureHistory.shared
        let count = history.entries.count
        historyHeaderItem?.title = count > 0 ? "撮った画像の履歴（\(count) 枚）" : "撮った画像の履歴"

        var items: [NSMenuItem] = []
        if history.entries.isEmpty {
            items.append(.disabled(title: AppSettings.shared.historyEnabled ? "まだ撮った画像はありません" : "履歴を残さない設定になっています"))
        }
        for entry in history.entries.prefix(recentHistoryCount) {
            let thumbnail = history.menuThumbnail(for: entry)
            let pin = makeHistoryItem(entry, title: CaptureHistoryRules.shortTitle(entry), action: #selector(pinHistoryItem(_:)))
            pin.image = thumbnail
            pin.toolTip = "押すと浮かせる（⌥ を押しながらでコピー）"
            let copy = makeHistoryItem(entry, title: "コピー：\(CaptureHistoryRules.shortTitle(entry))", action: #selector(copyHistoryItem(_:)))
            copy.image = thumbnail
            copy.isAlternate = true
            copy.keyEquivalentModifierMask = .option
            items += [pin, copy]
        }
        var index = menu.index(of: historyItem)
        for item in items {
            menu.insertItem(item, at: index)
            index += 1
        }
        recentHistoryItems = items
    }

    private func makeHistoryItem(_ entry: CaptureHistoryEntry, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = entry.id
        return item
    }

    // MARK: - メニューを開くとき

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            updateStatusMenu()
            return
        }
        if menu === windowListMenu {
            rebuildWindowList(menu)
        }
    }

    /// 「ウィンドウを選んでキャプチャ」の一覧を、いま開いているウィンドウで作り直す
    private func rebuildWindowList(_ menu: NSMenu) {
        menu.removeAllItems()
        let windows = WindowList.visibleWindows()
        if windows.isEmpty {
            menu.addItem(.disabled(title: "撮れるウィンドウがありません"))
            return
        }
        for info in windows {
            let item = NSMenuItem(title: info.displayName, action: #selector(captureListedWindow(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(info.id)
            if let icon = NSRunningApplication(processIdentifier: info.ownerPID)?.icon {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(releaseClickThrough):
            return PinManager.shared.hasClickThroughPins
        case #selector(performActionItem(_:)):
            guard let action = action(of: menuItem) else { return true }
            switch action {
            case .pinClipboard: return NSImage.canInit(with: .general)
            case .restoreClosed: return PinManager.shared.canRestore
            case .closeAll, .bringAllToFront: return PinManager.shared.hasPins
            default: return true
            }
        default:
            return true
        }
    }

    // MARK: - 押したとき

    @objc private func performActionItem(_ sender: NSMenuItem) {
        guard let action = action(of: sender) else { return }
        actions.perform(action)
    }

    @objc private func captureWithTimer(_ sender: NSMenuItem) {
        actions.captureWithTimer(sender.tag)
    }

    @objc private func captureListedWindow(_ sender: NSMenuItem) {
        actions.captureWindow(CGWindowID(sender.tag))
    }

    @objc private func pinHistoryItem(_ sender: NSMenuItem) {
        guard let entry = historyEntry(of: sender) else { return NSSound.beep() }
        CaptureHistory.shared.pin([entry])
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let entry = historyEntry(of: sender) else { return NSSound.beep() }
        CaptureHistory.shared.copy(entry)
    }

    /// メニューの項目に結びつけた操作
    private func action(of item: NSMenuItem) -> ShortcutAction? {
        (item.representedObject as? String).flatMap(ShortcutAction.init(rawValue:))
    }

    /// メニューの項目に結びつけた履歴
    private func historyEntry(of item: NSMenuItem) -> CaptureHistoryEntry? {
        guard let id = item.representedObject as? UUID else { return nil }
        return CaptureHistory.shared.entries.first { $0.id == id }
    }

    @objc private func releaseClickThrough() {
        PinManager.shared.releaseClickThrough()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openWelcome() {
        WelcomeWindowController.shared.show()
    }

    @objc private func openAbout() {
        NSApp.activate()
        // 「Pinshot について」は、渡さないと macOS が覚えているアイコン（古いもの・仮のもの）を出すので、はっきり渡す
        // 括弧で出るビルド番号（CFBundleVersion）は使っていないので出さず、「Version 0.1.0」だけにする
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.version: ""]
        if let icon = AppSupport.appIcon {
            options[.applicationIcon] = icon
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    // MARK: - ショートカットの表示

    /// 操作の項目に、割り当てたショートカットを出す。
    /// registered が false（ほかのアプリが同じキーを使っていて登録できなかった）なら、項目の名前で知らせる
    func showShortcut(_ shortcut: Shortcut?, registered: Bool, for action: ShortcutAction) {
        guard let item = actionItems[action] else { return }
        let title = actionTitles[action] ?? action.label
        if let shortcut, registered {
            item.title = title
            item.keyEquivalent = shortcut.key.count == 1 ? shortcut.key.lowercased() : ""
            item.keyEquivalentModifierMask = shortcut.menuModifierMask
        } else if let shortcut {
            // ほかのアプリが同じショートカットを使っていると登録できない
            item.title = "\(title)（\(shortcut.displayString) は使用中）"
            item.keyEquivalent = ""
        } else {
            item.title = title
            item.keyEquivalent = ""
        }
    }
}
