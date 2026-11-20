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
│   ├── CaptureCursors        キャプチャ中のカーソル
│   └── CaptureOutline        撮っている・録画している範囲の外側の点線の枠（スクロールキャプチャと録画で共通）
├── ScrollCapture/  スクロールキャプチャ
│   ├── ScrollCaptureController  始める・終わったら浮かせる
│   ├── ScrollTargetFinder    スクロール領域を探す（アクセシビリティ）
│   ├── ScrollCaptureSession  自動スクロールしながら撮る 1 回ぶんの流れ
│   ├── ScrollStitcher        撮った画像をつなぐ
│   └── ScrollCapturePanel    操作パネル
├── Recording/      画面の録画
│   ├── RecordingRules        録画の決まり（大きさを偶数に・座標・時間の表示・ファイル名・GIF のコマ数と大きさ・古い録画の整理。テストあり）
│   ├── ScreenRecorder        画面を受け取って MP4 に書く（ScreenCaptureKit の SCStream → AVAssetWriter）
│   ├── RecordingController   録画を始める・止める入口（赤い点線の枠・操作パネル・上限）
│   ├── RecordingStore        アプリの中に残す録画（期間と数で古いものを削除・本数と容量）
│   ├── RecordingPlayer       録画を浮かせてくり返し再生する窓（コピー・MP4 / GIF で保存・Finder で表示）
│   └── GIFExporter           録画から GIF を作る（テストあり）
├── Pin/            最前面に浮かぶウィンドウと、画像の表示・操作
│   ├── PinManager            浮かせている画像の一覧（閉じた画像を戻す・すべて閉じる・終了後も戻すための保存と復元 など）
│   ├── SavedPin・PinSessionStore  終了・再起動のあとも戻す状態（テストあり）と、その保存先（~/Library/Application Support/Pinshot/Pins に PNG と session.json）
│   ├── PinController(+◯◯)    画像 1 枚ぶんの操作（拡大縮小・不透明度・編集モード）。+Export はコピー・保存、+Menu は右クリックメニュー
│   ├── PinPanel・PinAppearance  画像のウィンドウ、画像の不透明度と拡大率（操作バーとツールバーで同じ値を見る）
│   ├── PinToolbarController  編集ツールバーのウィンドウ（出す・置く場所・説明のポップアップ）
│   ├── PinCanvasView(+◯◯)    画像と書き込みの表示と操作。役割ごとにファイルを分けている
│   │                         （+Cursor・+Mouse・+Keyboard・+Selection・+History・+Text・+TextRecognition・+TextMark・+Outside）
│   ├── PinAccessory          部品を画像の外に出す子ウィンドウ（閉じるボタンと操作バーはいつも。ほかは画像が小さくて中に入らないとき）
│   ├── PinBackdropView       画像のまわりの背景（余白・影）
│   ├── QuickActionBar・PinCloseButton  画像の下の操作バー（編集中はツールバーの上のバーとしても使う）と選んだ書き込みのバー、左上の外の閉じるボタン
│   ├── HUDView・HintBubble   「コピーしました」などのお知らせ、ツールバーの説明のポップアップ
│   ├── TextScanOverlay・RecognizedTextPopover  文字を読み取っている間・読み取ったあとの見た目と、読み取った文字の吹き出し（直してコピーし直せる）
│   └── ResizeEdges           端のドラッグで大きさを変える計算（テストあり）
├── History/        撮った画像と読み取った文字の履歴
│   ├── CaptureHistoryEntry   履歴の 1 枚と、残し方（期間・数）・日付ごとのまとめ方・表示の文字の決まり（テストあり）。期間と日付は文字の履歴にも使う
│   ├── CaptureHistory        画像の履歴の保存と読み込み（~/Library/Application Support/Pinshot/History に PNG・縮小画像・一覧の JSON）
│   ├── TextHistoryEntry・TextHistory  読み取った文字の履歴の 1 件と決まり（同じ文字はまとめる・探す。テストあり）と、その保存（同じフォルダに texts.json と、読み取った範囲の画像）
│   ├── ListSelection         一覧の選び方（クリック・⌘・shift・⌘A・矢印）。画像と文字の一覧で同じ（テストあり）
│   ├── CaptureHistoryWindowController・HistoryWindowView  履歴のウィンドウ（キー操作の振り分け・すべて消す前の確認）と、その中身（上の「画像 / 文字」の切り替え・表示方法・探す欄）
│   ├── CaptureHistoryViewModel・CaptureHistoryView  画像の一覧（複数選択・浮かせる・コピー・保存・消す）
│   ├── TextHistoryViewModel・TextHistoryView  文字の一覧と右の全文の欄（探す・複数選択・コピー・消す・直す・読み取った画像を浮かせる）
│   ├── HistoryComponents     画像と文字の一覧で同じ部品（日付の見出し・空のときの案内・小さな画像・行の背景・乗せたときのボタン・下の帯）
│   └── HistoryNotice         一覧の下に出す短い知らせ（「コピーしました」など）
├── Editor/         書き込みのデータ、描画、書き出し
│   ├── Annotation・AnnotationStyles・Tool・ToolGroup・RGBAColor   書き込みのデータ（Windows 版と形式をそろえる）と、ツールの組
│   ├── AnnotationRenderer・ImageEffects・ImageExporter 描画・モザイクとぼかし・書き出し
│   ├── TextRecognizer        文字の読み取り（Vision）と、読み取った文字を読む順に並べる決まり（テストあり）
│   ├── TextMarkLayout        文字マーカーを、ドラッグした所の文字に合わせて行ごとの四角にする決まりと、その形・画素を見て文字の線がある高さに合わせる処理（TextInk）（テストあり）
│   ├── AnnotationDocument    1 枚の画像の編集データ（書き込み・トリミング・元に戻す履歴）。変えるときは必ずここを通す
│   ├── EditHandle            選んだ書き込みのつまみ（形を直す）
│   ├── EditorState・EditorStyle・StylePreset・EditHistory  編集の状態・スタイルの保存・元に戻す
│   └── Toolbar/              ツールバー（SwiftUI）と、その部品
│       ├── EditorToolbar・ToolbarComponents・ToolbarMenuButtons  ツールバー本体、共通の部品、メニューを開くボタン
│       ├── TextStylePreview  文字ツールのオプションの見本（書き込みと同じ描き方で、次に入力する文字の見え方を出す）
│       ├── ViewControls      不透明度と拡大率（操作バーに出す。編集中もツールバーの上のバーとして同じ操作バーを出す）
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
    ├── ScreenGeometry        画面の座標の変換・部品を画面に収める位置・ツールバーと操作バーを画像の下に置く位置・操作パネルを置く位置（テストあり）
    ├── Permissions           画面収録・アクセシビリティの許可
    ├── GraphicsHelpers       画像の描き先を作る・画像のファイルを読む（読んだ時点で展開する。あとでファイルが消えても描ける）・縮める
    ├── EditableText          直せる文字の欄（右クリックは、短い日本語のメニューと、呼ぶ側が足す項目）
    ├── HoverCursor           部品の種類（押せる・動かせる・操作できない）で決めるカーソル
    ├── KeyCode・PercentText  キーの番号の名前、「80%」の表示
    ├── ImageSaver            PNG と録画のファイルを設定に合わせて保存する（浮かせた画像・履歴・録画から使う）
    ├── AppFolders            アプリのデータを置くフォルダ（履歴・浮かせていた画像・録画）
    ├── SaveLocation          保存したもの（画像・GIF・動画）を置く場所の決まり（保存先の中を種類ごと・月ごとに分ける。テストあり）
    └── ViewHelpers           前に出ていなくても押せるビュー・マウスの追跡・角の丸い枠（framedBox）・ドラッグで窓を動かす所（WindowDragArea）

PinshotTests/       画面に関係ない処理のテスト（make test）
```

## 設計のメモ

- 書き込みの座標は「元の画像のポイント座標（左上が原点）」で持ち、拡大縮小・トリミングしても変わらない
- 書き込み・トリミング・元に戻す履歴は `AnnotationDocument` が持つ。変更は必ずそのメソッドを通し、「元に戻すに積む」「番号を詰める」などの決まりをそこで守る
- 浮かせた画像やツールバーは、クリックしても前面を奪わないパネル（`OverlayPanel`）で作る。アプリ全体を前に出すと、ほかの浮かせた画像まで前に出てしまうため
- カーソル（`HoverRole`）・キーの番号（`KeyCode`）・画面に収める位置（`ScreenGeometry`）・背景の描き方（`ExportDecoration`）・ダイアログ（`AppAlert`）は、部品ごとに直接書かず、共通の部品を使う
- テスト（`PinshotTests/`）は、アプリを起動せずに動く。画面に関係ないソースを、テストのターゲットに直接入れている（`project.yml`）
