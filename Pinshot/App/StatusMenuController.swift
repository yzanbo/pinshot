import AppKit

/// メニューバーのアイコンと、押したときのメニュー
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var windowListMenu: NSMenu?
    /// 「ウィンドウを選んで録画」の一覧（メニューを開くたびに作り直す）
    private var recordWindowListMenu: NSMenu?
    /// ショートカットを表示するメニュー項目（操作ごと）と、そのもとの名前（タイマーの項目は「5 秒後」）
    private var actionItems: [ShortcutAction: NSMenuItem] = [:]
    private var actionTitles: [ShortcutAction: String] = [:]
    /// 操作ごとに割り当てたショートカットと、登録できたか（ほかのアプリが使っていると登録できない）
    private var shortcutStates: [ShortcutAction: (shortcut: Shortcut?, registered: Bool)] = [:]
    /// 画面収録の許可がないときだけ出す知らせ
    private var permissionNotice: MenuNotice?
    /// 自動で見つけた新しい版があるときだけ出す知らせ
    private var updateNotice: MenuNotice?
    /// 「アップデートを確認…」（更新の機能を使えるビルドだけ出す）
    private var checkForUpdatesItem: NSMenuItem?
    private var pinsHeaderItem: NSMenuItem?
    /// 録画している・上げている途中か（メニューバーのアイコンを変える）
    private var isRecording = false
    private var isUploading = false
    /// 新しい版があるときに、アイコンの右上に出す小さな丸
    private let updateBadge = UpdateBadgeView()
    /// 「読み取った文字 ▸」の項目と、その中のメニュー（開くたびに作り直す）
    private var textHistoryItem: NSMenuItem?
    private var textHistoryMenu: NSMenu?
    /// 「録画の音 ▸」の項目（いま選んでいる音を名前に出す）
    private var recordingAudioItem: NSMenuItem?
    /// 「読み取った文字 ▸」に並べる数
    private let recentTextCount = 10

    // MARK: - メニューを作る

    /// メニューバーにアイコンを出し、メニューを付ける
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Pinshot")
        item.button?.toolTip = "Pinshot"
        if let button = item.button {
            installUpdateBadge(on: button)
        }

        let menu = NSMenu()
        menu.delegate = self

        // 画面収録の許可がないときだけ、いちばん上で知らせる（メニューを開くたびに確かめる）
        permissionNotice = addNotice("画面収録の許可が必要です…", symbol: "exclamationmark.triangle.fill",
                                     color: .systemOrange, action: #selector(openWelcome), to: menu)
        // 自動で見つけた新しい版も、上で知らせる（選ぶと、更新の画面が出る。名前の版は、メニューを開くたびに入れる）
        updateNotice = addNotice("新しいバージョンがあります…", symbol: "arrow.down.circle.fill",
                                 color: .controlAccentColor, action: #selector(checkForUpdates), to: menu)

        // キャプチャ
        menu.addItem(.sectionHeader(title: "キャプチャ"))
        for action in ShortcutAction.captureActions where action != .captureTimer {
            addActionItem(action, to: menu)
        }

        // タイマー付き（5 秒のものは、ショートカットを割り当てられる）
        menu.addItem(makeTimerItem("タイマーでキャプチャ", action: #selector(captureWithTimer(_:)), shortcutAction: .captureTimer))
        // 開いているウィンドウの一覧から選ぶ（メニューを開くたびに作り直す）
        let (windowListItem, windowList) = makeWindowListItem("ウィンドウを選んでキャプチャ")
        menu.addItem(windowListItem)
        windowListMenu = windowList

        // 録画（キャプチャとは分け、キャプチャと同じ並びにする。録画中は「範囲を録画」が「録画を止める」になる）
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "録画"))
        for action in ShortcutAction.recordActions where action != .recordTimer {
            addActionItem(action, to: menu)
        }
        menu.addItem(makeTimerItem("タイマーで録画", action: #selector(recordWithTimer(_:)), shortcutAction: .recordTimer))
        let (recordWindowListItem, recordWindowList) = makeWindowListItem("ウィンドウを選んで録画")
        menu.addItem(recordWindowListItem)
        recordWindowListMenu = recordWindowList
        // 録画に入れる音（範囲を選ぶ画面の下のバーと同じ設定。選んだものは次の録画でも使う）
        let audioItem = makeItem("録画の音", symbol: "speaker.wave.2", action: nil)
        let audioMenu = NSMenu()
        for audio in RecordingAudio.allCases {
            let item = makeItem(audio.label, symbol: audio.symbolName, action: #selector(chooseRecordingAudio(_:)))
            item.representedObject = audio.rawValue
            item.toolTip = audio.detail
            audioMenu.addItem(item)
        }
        audioItem.submenu = audioMenu
        menu.addItem(audioItem)
        recordingAudioItem = audioItem

        // 履歴（撮った画像・読み取った文字・上げたもの。見出しは付けず、上下の区切り線で分ける。
        // 最近撮った画像は並べない。見るのは履歴のウィンドウ）
        menu.addItem(.separator())
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

        // アプリ
        menu.addItem(.separator())
        let settingsItem = makeItem("設定…", symbol: "gearshape", action: #selector(openSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(makeItem("使い方と許可…", symbol: "questionmark.circle", action: #selector(openWelcome)))
        // 更新の機能を使えるビルドだけ出す（公開鍵の入っていないビルドでは隠す。メニューを開くたびに確かめる）
        let checkItem = makeItem("アップデートを確認…", symbol: "arrow.down.circle", action: #selector(checkForUpdates))
        menu.addItem(checkItem)
        checkForUpdatesItem = checkItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Pinshot を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        statusMenu = menu
        // 前の起動で見つけて、まだ入れていない新しい版があれば、はじめから印を付ける
        updateStatusIcon()
        updateStatusMenu()
    }

    private func addActionItem(_ action: ShortcutAction, to menu: NSMenu) {
        let item = makeItem(action.label, symbol: action.symbolName, action: #selector(performActionItem(_:)))
        item.representedObject = action.rawValue
        menu.addItem(item)
        actionItems[action] = item
        actionTitles[action] = action.label
    }

    /// 「タイマーで〜」の項目（中に 3・5・10 秒後。5 秒後は shortcutAction のショートカットを出す）
    private func makeTimerItem(_ title: String, action: Selector, shortcutAction: ShortcutAction) -> NSMenuItem {
        let timerItem = makeItem(title, symbol: "timer", action: nil)
        let timerMenu = NSMenu()
        for seconds in CaptureOptions.timerChoices where seconds > 0 {
            let item = NSMenuItem(title: "\(seconds) 秒後", action: action, keyEquivalent: "")
            item.target = self
            item.tag = seconds
            timerMenu.addItem(item)
            if seconds == CaptureOptions.shortcutTimerSeconds {
                actionItems[shortcutAction] = item
                actionTitles[shortcutAction] = item.title
            }
        }
        timerItem.submenu = timerMenu
        return timerItem
    }

    /// 「ウィンドウを選んで〜」の項目と、その中のメニュー（開いているウィンドウの一覧。メニューを開くたびに作り直す）
    private func makeWindowListItem(_ title: String) -> (NSMenuItem, NSMenu) {
        let item = makeItem(title, symbol: "macwindow.on.rectangle", action: nil)
        let list = NSMenu()
        list.delegate = self
        item.submenu = list
        return (item, list)
    }

    private func makeItem(_ title: String, symbol: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = action == nil ? nil : self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    /// メニューの上に出す知らせ（色の付いたアイコンの項目と、その下の区切り線）を足す
    private func addNotice(_ title: String, symbol: String, color: NSColor, action: Selector, to menu: NSMenu) -> MenuNotice {
        let item = makeItem(title, symbol: symbol, action: action)
        item.image = item.image?.withSymbolConfiguration(.init(paletteColors: [color]))
        let separator = NSMenuItem.separator()
        menu.addItem(item)
        menu.addItem(separator)
        return MenuNotice(item: item, separator: separator)
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

    /// 自動で見つけた新しい版が変わった（見つけた・見てもらった）。アイコンの右上の小さな丸を合わせる
    func pendingUpdateDidChange() {
        updateStatusIcon()
    }

    /// メニューバーのアイコン（録画中は赤い ●、上げている間は ↑ の雲。どちらでもなければいつものカメラ）。
    /// 新しい版があるときは、どのアイコンでも右上に小さな丸を付ける
    private func updateStatusIcon() {
        let button = statusItem?.button
        let pendingVersion = AppUpdates.shared.pendingVersion
        if isRecording {
            button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Pinshot（録画中）")?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            button?.toolTip = "Pinshot（録画中。押して「録画を止める」）"
        } else if isUploading {
            button?.image = NSImage(systemSymbolName: "icloud.and.arrow.up", accessibilityDescription: "Pinshot（アップロード中）")
            button?.toolTip = "Pinshot（アップロード中）"
        } else {
            button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Pinshot")
            button?.toolTip = pendingVersion.map { "Pinshot（新しいバージョン \($0) があります）" } ?? "Pinshot"
        }
        updateBadge.isHidden = pendingVersion == nil
    }

    /// アイコンの右上に、新しい版の小さな丸を置く（ふだんは隠しておく）
    private func installUpdateBadge(on button: NSStatusBarButton) {
        updateBadge.isHidden = true
        updateBadge.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(updateBadge)
        NSLayoutConstraint.activate([
            updateBadge.widthAnchor.constraint(equalToConstant: UpdateBadgeView.diameter),
            updateBadge.heightAnchor.constraint(equalToConstant: UpdateBadgeView.diameter),
            updateBadge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            updateBadge.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
        ])
    }

    /// メニューを開くたびに、いまの状態（許可・新しい版・浮かせている画像の数・履歴の数）に合わせる
    private func updateStatusMenu() {
        permissionNotice?.isShown = !ScreenPermission.isGranted
        let updates = AppUpdates.shared
        updateNotice?.isShown = updates.pendingVersion != nil
        if let version = updates.pendingVersion {
            updateNotice?.item.title = "新しいバージョン \(version) があります…"
        }
        checkForUpdatesItem?.isHidden = !updates.isAvailable

        let pins = PinManager.shared
        pinsHeaderItem?.title = pins.pinCount > 0 ? "浮かせた画像（\(pins.pinCount) 枚）" : "浮かせた画像"
        let textCount = TextHistory.shared.entries.count
        textHistoryItem?.title = textCount > 0 ? "読み取った文字（\(textCount) 件）" : "読み取った文字"
        let audio = AppSettings.shared.recordingAudio
        recordingAudioItem?.title = "録画の音（\(audio.shortLabel)）"
        recordingAudioItem?.image = NSImage(systemSymbolName: audio.symbolName, accessibilityDescription: nil)
    }

    // MARK: - メニューを開くとき

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            updateStatusMenu()
            return
        }
        if menu === windowListMenu {
            rebuildWindowList(menu, action: #selector(captureListedWindow(_:)))
        }
        if menu === recordWindowListMenu {
            rebuildWindowList(menu, action: #selector(recordListedWindow(_:)))
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

    /// 「ウィンドウを選んでキャプチャ」「ウィンドウを選んで録画」の一覧を、いま開いているウィンドウで作り直す（押すと action）
    private func rebuildWindowList(_ menu: NSMenu, action: Selector) {
        menu.removeAllItems()
        let windows = WindowList.visibleWindows()
        if windows.isEmpty {
            menu.addItem(.disabled(title: "撮れるウィンドウがありません"))
            return
        }
        for info in windows {
            let item = NSMenuItem(title: info.displayName, action: action, keyEquivalent: "")
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
        case #selector(chooseRecordingAudio(_:)):
            menuItem.state = menuItem.representedObject as? String == AppSettings.shared.recordingAudio.rawValue ? .on : .off
            // 録画している間は変えない（いまの録画には効かないため）
            return !RecordingController.shared.isRecording
        case #selector(captureWithTimer(_:)), #selector(captureListedWindow(_:)),
             #selector(recordWithTimer(_:)), #selector(recordListedWindow(_:)):
            return !RecordingController.shared.isRecording
        case #selector(checkForUpdates):
            // 裏でダウンロードしている途中などは選べない（新しい版の知らせも同じ）
            return AppUpdates.shared.canCheck
        case #selector(performActionItem(_:)):
            guard let action = action(of: menuItem) else { return true }
            // 録画している間は、録画に写ってしまうので撮らない・ほかの録画は始めない（「録画を止める」は押せる）
            if RecordingController.shared.isRecording, ShortcutAction.screenActions.contains(action), action != .recordScreen {
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
        AppActions.shared.perform(action)
    }

    @objc private func captureWithTimer(_ sender: NSMenuItem) {
        AppActions.shared.captureWithTimer(sender.tag)
    }

    @objc private func recordWithTimer(_ sender: NSMenuItem) {
        AppActions.shared.recordWithTimer(sender.tag)
    }

    @objc private func recordListedWindow(_ sender: NSMenuItem) {
        AppActions.shared.recordWindow(id: CGWindowID(sender.tag))
    }

    @objc private func chooseRecordingAudio(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let audio = RecordingAudio(rawValue: raw) else { return }
        AppSettings.shared.recordingAudio = audio
    }

    @objc private func captureListedWindow(_ sender: NSMenuItem) {
        AppActions.shared.captureWindow(id: CGWindowID(sender.tag))
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

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openWelcome() {
        WelcomeWindowController.shared.show()
    }

    /// 新しい版がないかを確かめる（自動で見つけていた版があれば、その更新の画面を前に出す）
    @objc private func checkForUpdates() {
        AppUpdates.shared.check()
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

/// メニューの上に出す知らせ（項目と、その下の区切り線。いつも一緒に出し入れする）
private struct MenuNotice {
    let item: NSMenuItem
    let separator: NSMenuItem

    var isShown: Bool {
        get { !item.isHidden }
        nonmutating set {
            item.isHidden = !newValue
            separator.isHidden = !newValue
        }
    }
}

/// 新しい版があるときに、メニューバーのアイコンの右上に出す小さな丸
private final class UpdateBadgeView: NSView {
    static let diameter: CGFloat = 6

    override func draw(_ dirtyRect: NSRect) {
        // 色は描くたびに決める（外観やアクセントカラーが変わっても合うように）
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    /// アイコンのクリックを邪魔しない
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
