# コードの構成

```
Pinshot/
├── App/            起動と、アプリ全体に関わるもの
│   ├── AppDelegate           起動・グローバルショートカットの登録・操作の振り分け
│   ├── HotKey・ShortcutKeyTap  グローバルショートカット（Carbon）と、メニューを開いている間もショートカットを受けるキーの見張り
│   ├── StatusMenuController  メニューバーのアイコンとメニュー
│   └── AppSupport・AppRelauncher  メインメニュー・アプリのアイコン・⌘Q の扱い、起動し直し
├── Screenshot/     画面の撮影（ScreenCaptureKit）と範囲の選択
│   ├── CaptureController     撮る流れ（選ぶ → タイマー → 浮かせる）
│   ├── ScreenCapturer・WindowList  画面・ウィンドウを撮る、画面に出ているウィンドウの一覧
│   ├── CaptureTypes          モード・撮るもの・撮った画面などの型
│   ├── CaptureShield         ショートカットを押した瞬間に画面にかぶせる透明なウィンドウ（そのまま範囲を選ぶ画面になる）
│   ├── SelectionController   範囲を選ぶ画面（画面ごとのウィンドウ・モードの切り替え）
│   ├── SelectionView(+Drawing)  選ぶ操作（マウス・スクロール領域を探す）と、範囲・ルーペ・座標の描画
│   ├── CaptureModeBar・CountdownPanel  モードとタイマーを選ぶバー（SwiftUI）、タイマーの秒読み
│   └── CaptureCursors        キャプチャ中のカーソル
├── ScrollCapture/  スクロールキャプチャ
│   ├── ScrollCaptureController  始める・終わったら浮かせる
│   ├── ScrollTargetFinder    スクロール領域を探す（アクセシビリティ）
│   ├── ScrollCaptureSession  自動スクロールしながら撮る 1 回ぶんの流れ
│   ├── ScrollStitcher        撮った画像をつなぐ
│   └── ScrollCapturePanel    操作パネルと点線の枠
├── Pin/            最前面に浮かぶウィンドウと、画像の表示・操作
│   ├── PinManager            浮かせている画像の一覧（閉じた画像を戻す・すべて閉じる・終了後も戻すための保存と復元 など）
│   ├── SavedPin・PinSessionStore  終了・再起動のあとも戻す状態（テストあり）と、その保存先（~/Library/Application Support/Pinshot/Pins に PNG と session.json）
│   ├── PinController(+◯◯)    画像 1 枚ぶんの操作（拡大縮小・不透明度・編集モード）。+Export はコピー・保存、+Menu は右クリックメニュー
│   ├── PinPanel・PinAppearance  画像のウィンドウ、画像の不透明度と拡大率（操作バーとツールバーで同じ値を見る）
│   ├── PinToolbarController  編集ツールバーのウィンドウ（出す・置く場所・説明のポップアップ）
│   ├── PinCanvasView(+◯◯)    画像と書き込みの表示と操作。役割ごとにファイルを分けている
│   │                         （+Cursor・+Mouse・+Keyboard・+Selection・+History・+Text・+Outside）
│   ├── PinAccessory          部品を画像の外に出す子ウィンドウ（閉じるボタンと操作バーはいつも。ほかは画像が小さくて中に入らないとき）
│   ├── PinBackdropView       画像のまわりの背景（余白・影）
│   ├── QuickActionBar・PinCloseButton  画像の下の操作バーと選んだ書き込みのバー、左上の外の閉じるボタン
│   ├── HUDView・HintBubble   「コピーしました」などのお知らせ、ツールバーの説明のポップアップ
│   └── ResizeEdges           端のドラッグで大きさを変える計算（テストあり）
├── History/        撮った画像の履歴
│   ├── CaptureHistoryEntry   履歴の 1 枚と、残し方（期間・枚数）・日付ごとのまとめ方・表示の文字の決まり（テストあり）
│   ├── CaptureHistory        履歴の保存と読み込み（~/Library/Application Support/Pinshot/History に PNG・縮小画像・一覧の JSON）
│   └── CaptureHistoryWindowController・CaptureHistoryViewModel・CaptureHistoryView   一覧のウィンドウ（複数選択・浮かせる・コピー・保存・消す）
├── Editor/         書き込みのデータ、描画、書き出し
│   ├── Annotation・AnnotationStyles・Tool・ToolGroup・RGBAColor   書き込みのデータ（Windows 版と形式をそろえる）と、ツールの組
│   ├── AnnotationRenderer・ImageEffects・ImageExporter 描画・モザイクとぼかし・書き出し
│   ├── AnnotationDocument    1 枚の画像の編集データ（書き込み・トリミング・元に戻す履歴）。変えるときは必ずここを通す
│   ├── EditHandle            選んだ書き込みのつまみ（形を直す）
│   ├── EditorState・EditorStyle・StylePreset・EditHistory  編集の状態・スタイルの保存・元に戻す
│   └── Toolbar/              ツールバー（SwiftUI）と、その部品
│       ├── EditorToolbar・ToolbarComponents・ToolbarMenuButtons  ツールバー本体、共通の部品、メニューを開くボタン
│       ├── ViewControls      不透明度と拡大率（操作バーとツールバーの両方に出す）
│       └── FontMenu・TextInputController・ColorPanelController  フォントのメニュー、数字や名前の入力欄、カラーパネル
├── Assets.xcassets/ アプリのアイコン（scripts/make-app-icon.swift で描いて書き出す）
├── Settings/       設定の値（AppSettings・Shortcut・ExportDecoration）と画面
│   ├── SettingsWindowController  設定のウィンドウ（タブ）
│   ├── General・Pin・Export・History・ShortcutSettingsView   タブごとの画面
│   ├── SettingsComponents    設定の画面の共通の部品（枠・説明の文字・選択肢の Picker）
│   └── WelcomeView           使い方と許可の案内
└── Support/        どこからも使う部品
    ├── OverlayPanel          枠のない、前面を奪わないパネルの土台
    ├── PopupMenu・OpenMenus  項目の並びからメニューを作る、開いているメニューを覚えて閉じる
    ├── AppAlert              確かめる・知らせるダイアログ（アプリのアイコン・ウィンドウのシート）
    ├── ScreenGeometry        画面の座標の変換・部品を画面に収める位置・ツールバーと操作バーを画像の下に置く位置（テストあり）
    ├── Permissions           画面収録・アクセシビリティの許可
    ├── GraphicsHelpers       画像の描き先を作る・画像のファイルを読む
    ├── HoverCursor           部品の種類（押せる・動かせる・操作できない）で決めるカーソル
    ├── KeyCode・PercentText  キーの番号の名前、「80%」の表示
    ├── ImageSaver            PNG を設定に合わせて保存する（浮かせた画像と履歴から使う）
    ├── AppFolders            アプリのデータを置くフォルダ（履歴・浮かせていた画像）
    └── ViewHelpers           前に出ていなくても押せるビュー・マウスの追跡

PinshotTests/       画面に関係ない処理のテスト（make test）
```

## 設計のメモ

- 書き込みの座標は「元の画像のポイント座標（左上が原点）」で持ち、拡大縮小・トリミングしても変わらない
- 書き込み・トリミング・元に戻す履歴は `AnnotationDocument` が持つ。変更は必ずそのメソッドを通し、「元に戻すに積む」「番号を詰める」などの決まりをそこで守る
- 浮かせた画像やツールバーは、クリックしても前面を奪わないパネル（`OverlayPanel`）で作る。アプリ全体を前に出すと、ほかの浮かせた画像まで前に出てしまうため
- カーソル（`HoverRole`）・キーの番号（`KeyCode`）・画面に収める位置（`ScreenGeometry`）・背景の描き方（`ExportDecoration`）・ダイアログ（`AppAlert`）は、部品ごとに直接書かず、共通の部品を使う
- テスト（`PinshotTests/`）は、アプリを起動せずに動く。画面に関係ないソースを、テストのターゲットに直接入れている（`project.yml`）
