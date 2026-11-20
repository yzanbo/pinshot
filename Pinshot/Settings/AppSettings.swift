import AppKit
import Combine

/// 閉じるボタン（×）の出し方
enum CloseButtonMode: String, CaseIterable, Identifiable {
    case always
    case hover
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .always: "常に表示"
        case .hover: "マウスを乗せたときだけ"
        case .hidden: "表示しない"
        }
    }
}

/// 保存の仕方
enum SaveMode: String, CaseIterable, Identifiable {
    case ask
    case folder

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: "毎回、保存先を聞く"
        case .folder: "決めたフォルダにすぐ保存"
        }
    }
}

/// 画面の見た目（ツールバー・メニュー・設定などのライト / ダーク）
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "システム"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    /// アプリ全体に設定する見た目（nil ならシステムの設定に合わせる）
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// アプリの設定。変えるとすぐ UserDefaults に保存する
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let shortcut = "settings.shortcut"
        static let shortcuts = "settings.shortcuts"
        static let copyAfterCapture = "settings.copyAfterCapture"
        static let closeButtonMode = "settings.closeButtonMode"
        static let defaultOpacity = "settings.defaultOpacity"
        static let annotationShadow = "settings.annotationShadow"
        static let saveMode = "settings.saveMode"
        static let saveFolder = "settings.saveFolder"
        static let showsQuickActions = "settings.showsQuickActions"
        static let alwaysOnTop = "settings.alwaysOnTop"
        static let detailedCaptureUI = "settings.detailedCaptureUI"
        static let exportDecoration = "settings.exportDecoration"
        static let appearance = "settings.appearance"
        static let historyEnabled = "settings.historyEnabled"
        static let historyPeriod = "settings.historyPeriod"
        static let historyLimit = "settings.historyLimit"
        static let historyLayout = "settings.historyLayout"
    }

    private let defaults = UserDefaults.standard

    /// 操作ごとのショートカット（割り当てていない操作は入っていない）
    @Published private(set) var shortcuts: [ShortcutAction: Shortcut] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            if let data = try? JSONEncoder().encode(stored) {
                defaults.set(data, forKey: Key.shortcuts)
            }
        }
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        shortcuts[action]
    }

    /// ショートカットを割り当てる（nil で外す）。
    /// ほかの操作と同じキーだったら、そちらから外して、その操作を返す
    @discardableResult
    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) -> ShortcutAction? {
        var updated = shortcuts
        var removedFrom: ShortcutAction?
        if let shortcut, let other = updated.first(where: { $0.key != action && $0.value == shortcut })?.key {
            updated[other] = nil
            removedFrom = other
        }
        updated[action] = shortcut
        shortcuts = updated
        return removedFrom
    }

    func resetShortcuts() {
        shortcuts = Self.defaultShortcuts
    }

    private static var defaultShortcuts: [ShortcutAction: Shortcut] {
        var result: [ShortcutAction: Shortcut] = [:]
        for action in ShortcutAction.allCases {
            if let shortcut = action.defaultShortcut { result[action] = shortcut }
        }
        return result
    }

    /// 画面の見た目（システム・ライト・ダーク）。変えるとすぐアプリ全体に反映する（AppDelegate）
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// 撮った画像を履歴に残す
    @Published var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) }
    }

    /// 履歴を残す期間
    @Published var historyPeriod: HistoryPeriod {
        didSet { defaults.set(historyPeriod.rawValue, forKey: Key.historyPeriod) }
    }

    /// 履歴に残す枚数の上限
    @Published var historyLimit: HistoryLimit {
        didSet { defaults.set(historyLimit.rawValue, forKey: Key.historyLimit) }
    }

    /// 履歴の一覧の表示方法
    @Published var historyLayout: HistoryLayout {
        didSet { defaults.set(historyLayout.rawValue, forKey: Key.historyLayout) }
    }

    /// 撮ったらすぐクリップボードにもコピーする
    @Published var copyAfterCapture: Bool {
        didSet { defaults.set(copyAfterCapture, forKey: Key.copyAfterCapture) }
    }

    /// 保存・コピーのときに付ける背景
    @Published var exportDecoration: ExportDecoration {
        didSet {
            if let data = try? JSONEncoder().encode(exportDecoration) {
                defaults.set(data, forKey: Key.exportDecoration)
            }
        }
    }

    /// キャプチャ中に、画面を暗くし、ルーペ・十字線を出す（オフならシンプルな表示。モードバーはどちらでも出す）
    @Published var detailedCaptureUI: Bool {
        didSet { defaults.set(detailedCaptureUI, forKey: Key.detailedCaptureUI) }
    }

    /// 浮かせた画像を、常にほかのウィンドウより前に出す
    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    /// マウスを乗せたら、編集・コピー・保存のバーを出す
    @Published var showsQuickActions: Bool {
        didSet { defaults.set(showsQuickActions, forKey: Key.showsQuickActions) }
    }

    @Published var closeButtonMode: CloseButtonMode {
        didSet { defaults.set(closeButtonMode.rawValue, forKey: Key.closeButtonMode) }
    }

    /// 浮かせたときの不透明度（0.2〜1）
    @Published var defaultOpacity: Double {
        didSet { defaults.set(defaultOpacity, forKey: Key.defaultOpacity) }
    }

    /// 書き込みに薄い影を付ける
    @Published var annotationShadow: Bool {
        didSet { defaults.set(annotationShadow, forKey: Key.annotationShadow) }
    }

    @Published var saveMode: SaveMode {
        didSet { defaults.set(saveMode.rawValue, forKey: Key.saveMode) }
    }

    @Published var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: Key.saveFolder) }
    }

    /// ショートカットを記録している操作（記録中は、すべてのショートカットを止める）
    @Published var recordingAction: ShortcutAction?

    var isRecordingShortcut: Bool { recordingAction != nil }

    /// ほかのアプリが同じキーを使っていて、登録できなかったショートカットの操作（保存はしない）
    @Published var unavailableShortcuts: Set<ShortcutAction> = []

    private init() {
        if let data = defaults.data(forKey: Key.shortcuts),
           let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            var restored: [ShortcutAction: Shortcut] = [:]
            for (key, value) in saved {
                if let action = ShortcutAction(rawValue: key) { restored[action] = value }
            }
            shortcuts = restored
        } else if let data = defaults.data(forKey: Key.shortcut),
                  let old = try? JSONDecoder().decode(Shortcut.self, from: data) {
            // 前の版（範囲のショートカットだけ）の設定を引き継ぐ
            shortcuts = [.captureRegion: old]
        } else {
            shortcuts = Self.defaultShortcuts
        }
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        historyEnabled = defaults.object(forKey: Key.historyEnabled) as? Bool ?? true
        historyPeriod = (defaults.object(forKey: Key.historyPeriod) as? Int).flatMap(HistoryPeriod.init(rawValue:)) ?? .month
        historyLimit = (defaults.object(forKey: Key.historyLimit) as? Int).flatMap(HistoryLimit.init(rawValue:)) ?? .hundred
        historyLayout = defaults.string(forKey: Key.historyLayout).flatMap(HistoryLayout.init(rawValue:)) ?? .largeGrid
        copyAfterCapture = defaults.object(forKey: Key.copyAfterCapture) as? Bool ?? false
        showsQuickActions = defaults.object(forKey: Key.showsQuickActions) as? Bool ?? true
        alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? true
        detailedCaptureUI = defaults.bool(forKey: Key.detailedCaptureUI)
        exportDecoration = defaults.data(forKey: Key.exportDecoration)
            .flatMap { try? JSONDecoder().decode(ExportDecoration.self, from: $0) } ?? ExportDecoration()
        closeButtonMode = defaults.string(forKey: Key.closeButtonMode).flatMap(CloseButtonMode.init(rawValue:)) ?? .always
        defaultOpacity = defaults.object(forKey: Key.defaultOpacity) as? Double ?? 1
        annotationShadow = defaults.object(forKey: Key.annotationShadow) as? Bool ?? true
        saveMode = defaults.string(forKey: Key.saveMode).flatMap(SaveMode.init(rawValue:)) ?? .ask
        if let path = defaults.string(forKey: Key.saveFolder) {
            saveFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveFolder = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
    }
}
