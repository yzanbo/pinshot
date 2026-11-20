import AppKit
import Combine

/// 閉じるボタン（×）と操作バーの出し方
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
        static let separatesSaveFoldersByKind = "settings.separatesSaveFoldersByKind"
        static let separatesSaveFoldersByMonth = "settings.separatesSaveFoldersByMonth"
        static let recordingPeriod = "settings.recordingPeriod"
        static let recordingLimit = "settings.recordingLimit"
        static let showsQuickActions = "settings.showsQuickActions"
        static let alwaysOnTop = "settings.alwaysOnTop"
        static let detailedCaptureUI = "settings.detailedCaptureUI"
        static let exportDecoration = "settings.exportDecoration"
        static let appearance = "settings.appearance"
        static let historyEnabled = "settings.historyEnabled"
        static let textHistoryEnabled = "settings.textHistoryEnabled"
        static let historyPeriod = "settings.historyPeriod"
        static let historyLimit = "settings.historyLimit"
        static let textHistoryPeriod = "settings.textHistoryPeriod"
        static let textHistoryLimit = "settings.textHistoryLimit"
        static let historyLayout = "settings.historyLayout"
        static let textHistoryLayout = "settings.textHistoryLayout"
        static let restorePins = "settings.restorePins"
        static let textPopoverClosesOnOutsideClick = "settings.textPopoverClosesOnOutsideClick"
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

    /// 読み取った文字を履歴に残す
    @Published var textHistoryEnabled: Bool {
        didSet { defaults.set(textHistoryEnabled, forKey: Key.textHistoryEnabled) }
    }

    /// 撮った画像の履歴を残す期間
    @Published var historyPeriod: HistoryPeriod {
        didSet { defaults.set(historyPeriod.rawValue, forKey: Key.historyPeriod) }
    }

    /// 撮った画像の履歴に残す数の上限
    @Published var historyLimit: HistoryLimit {
        didSet { defaults.set(historyLimit.rawValue, forKey: Key.historyLimit) }
    }

    /// 読み取った文字の履歴を残す期間
    @Published var textHistoryPeriod: HistoryPeriod {
        didSet { defaults.set(textHistoryPeriod.rawValue, forKey: Key.textHistoryPeriod) }
    }

    /// 読み取った文字の履歴に残す数の上限
    @Published var textHistoryLimit: HistoryLimit {
        didSet { defaults.set(textHistoryLimit.rawValue, forKey: Key.textHistoryLimit) }
    }

    /// 履歴の一覧の表示方法
    @Published var historyLayout: HistoryLayout {
        didSet { defaults.set(historyLayout.rawValue, forKey: Key.historyLayout) }
    }

    /// 読み取った文字の履歴の一覧の表示方法
    @Published var textHistoryLayout: TextHistoryLayout {
        didSet { defaults.set(textHistoryLayout.rawValue, forKey: Key.textHistoryLayout) }
    }

    /// 終了・再起動のあとも、浮かせていた画像と閉じた画像を戻す
    @Published var restorePins: Bool {
        didSet { defaults.set(restorePins, forKey: Key.restorePins) }
    }

    /// 読み取った文字の吹き出しを、外を押したら閉じる（オフなら「閉じる」か esc でだけ閉じる）
    @Published var textPopoverClosesOnOutsideClick: Bool {
        didSet { defaults.set(textPopoverClosesOnOutsideClick, forKey: Key.textPopoverClosesOnOutsideClick) }
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

    /// 画像の下に操作バーを出す（いつ出すかは closeButtonMode に従う。オフなら、編集するまで画像の下に何も出さない）
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

    /// 保存先（親）。保存したもの（画像・GIF・動画）は、この中に置く
    @Published var saveFolder: URL {
        didSet { defaults.set(saveFolder.path, forKey: Key.saveFolder) }
    }

    /// 保存先の中を、種類ごとのフォルダ（画像 / GIF / 動画）に分ける
    @Published var separatesSaveFoldersByKind: Bool {
        didSet { defaults.set(separatesSaveFoldersByKind, forKey: Key.separatesSaveFoldersByKind) }
    }

    /// 保存先の中を、月ごとのフォルダ（2026-11 など）に分ける
    @Published var separatesSaveFoldersByMonth: Bool {
        didSet { defaults.set(separatesSaveFoldersByMonth, forKey: Key.separatesSaveFoldersByMonth) }
    }

    /// 保存先の初期設定（「ピクチャ」フォルダの中の Pinshot。~/Pictures/Pinshot）
    static var defaultSaveFolder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("Pinshot", isDirectory: true)
    }

    /// 保存先のフォルダを作る（なければ。起動したとき・保存するとき・Finder で開くときに呼ぶ）。作った（ある）フォルダを返す
    @discardableResult
    func prepareSaveFolder(for kind: ExportKind? = nil) -> URL {
        let folder = kind.map { saveFolder(for: $0) } ?? saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// kind を保存するフォルダ（保存先の中を、設定に合わせて種類ごと・月ごとに分ける）
    func saveFolder(for kind: ExportKind, date: Date = Date()) -> URL {
        SaveLocation.folder(base: saveFolder, kind: kind, byKind: separatesSaveFoldersByKind, byMonth: separatesSaveFoldersByMonth, date: date)
    }

    /// 録画をアプリの中に残す期間
    @Published var recordingPeriod: HistoryPeriod {
        didSet { defaults.set(recordingPeriod.rawValue, forKey: Key.recordingPeriod) }
    }

    /// 録画をアプリの中に残す数の上限
    @Published var recordingLimit: RecordingLimit {
        didSet { defaults.set(recordingLimit.rawValue, forKey: Key.recordingLimit) }
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
        appearance = defaults.option(Key.appearance, default: .system)
        historyEnabled = defaults.bool(Key.historyEnabled, default: true)
        textHistoryEnabled = defaults.bool(Key.textHistoryEnabled, default: true)
        let imagePeriod: HistoryPeriod = defaults.option(Key.historyPeriod, default: .month)
        let imageLimit: HistoryLimit = defaults.option(Key.historyLimit, default: .hundred)
        historyPeriod = imagePeriod
        historyLimit = imageLimit
        // 文字の履歴の期間と数は、分ける前は画像と同じ設定を使っていたので、まだ決めていなければ画像の設定を引き継ぐ
        textHistoryPeriod = defaults.option(Key.textHistoryPeriod, default: imagePeriod)
        textHistoryLimit = defaults.option(Key.textHistoryLimit, default: imageLimit)
        historyLayout = defaults.option(Key.historyLayout, default: .largeGrid)
        textHistoryLayout = defaults.option(Key.textHistoryLayout, default: .standard)
        restorePins = defaults.bool(Key.restorePins, default: true)
        textPopoverClosesOnOutsideClick = defaults.bool(Key.textPopoverClosesOnOutsideClick, default: false)
        copyAfterCapture = defaults.bool(Key.copyAfterCapture, default: false)
        showsQuickActions = defaults.bool(Key.showsQuickActions, default: true)
        alwaysOnTop = defaults.bool(Key.alwaysOnTop, default: true)
        detailedCaptureUI = defaults.bool(Key.detailedCaptureUI, default: false)
        exportDecoration = defaults.data(forKey: Key.exportDecoration)
            .flatMap { try? JSONDecoder().decode(ExportDecoration.self, from: $0) } ?? ExportDecoration()
        closeButtonMode = defaults.option(Key.closeButtonMode, default: .always)
        defaultOpacity = defaults.object(forKey: Key.defaultOpacity) as? Double ?? 1
        annotationShadow = defaults.bool(Key.annotationShadow, default: true)
        saveMode = defaults.option(Key.saveMode, default: .ask)
        separatesSaveFoldersByKind = defaults.bool(Key.separatesSaveFoldersByKind, default: false)
        separatesSaveFoldersByMonth = defaults.bool(Key.separatesSaveFoldersByMonth, default: false)
        recordingPeriod = defaults.option(Key.recordingPeriod, default: .month)
        recordingLimit = defaults.option(Key.recordingLimit, default: .twenty)
        if let path = defaults.string(forKey: Key.saveFolder) {
            saveFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            saveFolder = Self.defaultSaveFolder
        }
    }
}

private extension UserDefaults {
    /// 保存した真偽値（まだ保存していなければ fallback）
    func bool(_ key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }

    /// 保存した選択肢（まだ保存していない・いまはない値なら fallback）
    func option<Option: RawRepresentable>(_ key: String, default fallback: Option) -> Option {
        (object(forKey: key) as? Option.RawValue).flatMap(Option.init(rawValue:)) ?? fallback
    }
}
