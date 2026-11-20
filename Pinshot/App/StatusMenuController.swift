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
    /// ショートカットを表示するメニュー項目（操作ごと）と、そのもとの名前（タイマーの項目は「5 秒後」）
    private var actionItems: [ShortcutAction: NSMenuItem] = [:]
    private var actionTitles: [ShortcutAction: String] = [:]
    /// 操作ごとに割り当てたショートカットと、登録できたか（ほかのアプリが使っていると登録できない）
    private var shortcutStates: [ShortcutAction: (shortcut: Shortcut?, registered: Bool)] = [:]
    /// 画面収録の許可がないときだけ出す項目（知らせと区切り線）
    private var permissionItems: [NSMenuItem] = []
    private var pinsHeaderItem: NSMenuItem?
    private var clickThroughItem: NSMenuItem?
    /// 「撮った画像の履歴」の見出し（枚数を出す）
    private var historyHeaderItem: NSMenuItem?
    /// 録画している・上げている途中か（メニューバーのアイコンを変える）
    private var isRecording = false
    private var isUploading = false
    /// 「読み取った文字 ▸」の項目と、その中のメニュー（開くたびに作り直す）
    private var textHistoryItem: NSMenuItem?
    private var textHistoryMenu: NSMenu?
    /// 「読み取った文字 ▸」に並べる数
    private let recentTextCount = 10

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

        // 録画（キャプチャとは分ける。録画中は「録画を止める」になる）
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "録画"))
        for action in ShortcutAction.recordActions {
            addActionItem(action, to: menu)
        }

        // 撮った画像の履歴（見出しに枚数を出す。最近撮った画像は並べない。見るのは履歴のウィンドウ）
        menu.addItem(.separator())
        let historyHeader = NSMenuItem.sectionHeader(title: "撮った画像の履歴")
        menu.addItem(historyHeader)
        historyHeaderItem = historyHeader
        for action in ShortcutAction.historyActions {
            addActionItem(action, to: menu)
        }
        let textItem = makeItem("読み取った文字", symbol: "text.viewfinder", action: nil)
        let textMenu = NSMenu()
        textMenu.delegate = self
        textItem.submenu = textMenu
        menu.addItem(textItem)
        textHistoryItem = textItem
        textHistoryMenu = textMenu

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

    /// 録画を始めた・止めたとき。録画中は、メニューバーのアイコンを赤い ● にし、「画面を録画」を「録画を止める」にする
    func setRecording(_ recording: Bool) {
        isRecording = recording
        updateStatusIcon()
        refreshActionItem(.recordScreen)
    }

    /// 上げ始めた・上げ終えたとき。上げている間は、メニューバーのアイコンを「上げている」印にする
    func setUploading(_ uploading: Bool) {
        isUploading = uploading
        updateStatusIcon()
    }

    /// メニューバーのアイコン（録画中は赤い ●、上げている間は ↑ の雲。どちらでもなければいつものカメラ）
    private func updateStatusIcon() {
        let button = statusItem?.button
        if isRecording {
            button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Pinshot（録画中）")?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            button?.toolTip = "Pinshot（録画中。押して「録画を止める」）"
        } else if isUploading {
            button?.image = NSImage(systemSymbolName: "icloud.and.arrow.up", accessibilityDescription: "Pinshot（アップロード中）")
            button?.toolTip = "Pinshot（アップロード中）"
        } else {
            button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Pinshot")
            button?.toolTip = "Pinshot"
        }
    }

    /// メニューを開くたびに、いまの状態（許可・浮かせている画像の数・クリック透過）に合わせる
    private func updateStatusMenu() {
        let needsPermission = !ScreenPermission.isGranted
        permissionItems.forEach { $0.isHidden = !needsPermission }

        let pins = PinManager.shared
        pinsHeaderItem?.title = pins.pinCount > 0 ? "浮かせた画像（\(pins.pinCount) 枚）" : "浮かせた画像"
        clickThroughItem?.isHidden = !pins.hasClickThroughPins
        let historyCount = CaptureHistory.shared.entries.count
        historyHeaderItem?.title = historyCount > 0 ? "撮った画像の履歴（\(historyCount) 枚）" : "撮った画像の履歴"
        let textCount = TextHistory.shared.entries.count
        textHistoryItem?.title = textCount > 0 ? "読み取った文字（\(textCount) 件）" : "読み取った文字"
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
        if menu === textHistoryMenu {
            rebuildTextHistory(menu)
        }
    }

    /// 「読み取った文字」の中を、最近読み取った文字で作り直す（押すとコピー）
    private func rebuildTextHistory(_ menu: NSMenu) {
        menu.removeAllItems()
        let history = TextHistory.shared
        if history.entries.isEmpty {
            menu.addItem(.disabled(title: AppSettings.shared.textHistoryEnabled ? "まだ読み取った文字はありません" : "読み取った文字を残さない設定になっています"))
        } else {
            menu.addItem(.sectionHeader(title: "押すとコピー"))
        }
        for entry in history.entries.prefix(recentTextCount) {
            let item = NSMenuItem(title: TextHistoryRules.preview(entry.text), action: #selector(copyTextHistoryItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.toolTip = entry.text
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(makeItem("文字の履歴を開く…", symbol: "list.bullet.rectangle", action: #selector(openTextHistory)))
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
        case #selector(captureWithTimer(_:)), #selector(captureListedWindow(_:)):
            return !RecordingController.shared.isRecording
        case #selector(releaseClickThrough):
            return PinManager.shared.hasClickThroughPins
        case #selector(performActionItem(_:)):
            guard let action = action(of: menuItem) else { return true }
            // 録画している間は、録画に写ってしまうので撮らない（「録画を止める」は押せる）
            if RecordingController.shared.isRecording, ShortcutAction.captureActions.contains(action) {
                return false
            }
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

    @objc private func copyTextHistoryItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let entry = TextHistory.shared.entries.first(where: { $0.id == id }) else { return NSSound.beep() }
        TextHistory.shared.copy(entry.text)
    }

    @objc private func openTextHistory() {
        CaptureHistoryWindowController.shared.show(tab: .texts)
    }

    /// メニューの項目に結びつけた操作
    private func action(of item: NSMenuItem) -> ShortcutAction? {
        (item.representedObject as? String).flatMap(ShortcutAction.init(rawValue:))
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
        shortcutStates[action] = (shortcut, registered)
        refreshActionItem(action)
    }

    /// 操作の項目の名前・アイコン・キーを、いまの状態（録画中か・割り当てたショートカット・登録できたか）から決める。
    /// 項目を書き換えるのはここだけにする（録画の開始・停止とショートカットの登録し直しが、別々に名前を書き換えると、
    /// 録画中に設定を閉じたときに「録画を止める」が「画面を録画」に戻るなど、片方の表示が消えるため）
    private func refreshActionItem(_ action: ShortcutAction) {
        guard let item = actionItems[action] else { return }
        let title: String
        if action == .recordScreen {
            // 録画中は「録画を止める」にする
            title = isRecording ? "録画を止める" : action.label
            item.image = NSImage(systemSymbolName: isRecording ? "stop.circle" : action.symbolName, accessibilityDescription: nil)
        } else {
            title = actionTitles[action] ?? action.label
        }
        let state = shortcutStates[action]
        if let shortcut = state?.shortcut, state?.registered == true {
            item.title = title
            item.keyEquivalent = shortcut.key.count == 1 ? shortcut.key.lowercased() : ""
            item.keyEquivalentModifierMask = shortcut.menuModifierMask
        } else if let shortcut = state?.shortcut {
            // ほかのアプリが同じショートカットを使っていると登録できない
            item.title = "\(title)（\(shortcut.displayString) は使用中）"
            item.keyEquivalent = ""
        } else {
            item.title = title
            item.keyEquivalent = ""
        }
    }
}
