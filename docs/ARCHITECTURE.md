# コードの構成

```
Pinshot/
├── App/            起動とグローバルショートカット（AppDelegate・HotKey。メニューを開いている間は ShortcutKeyTap でも受ける）、メニューバーのメニュー（StatusMenuController）
├── Screenshot/     画面の撮影（ScreenCaptureKit）と範囲の選択
│   ├── CaptureController     撮る流れ（選ぶ → タイマー → 浮かせる）
│   ├── SelectionController   範囲を選ぶ画面（画面ごとのウィンドウ・モードの切り替え）
│   ├── SelectionView(+Drawing)  選ぶ操作（マウス・スクロール領域を探す）と、範囲・ルーペ・座標の描画
│   └── CaptureModeBar        モードとタイマーを選ぶバー（SwiftUI）
├── ScrollCapture/  スクロールキャプチャ
│   ├── ScrollTargetFinder    スクロール領域を探す（アクセシビリティ）
│   ├── ScrollCaptureSession  自動スクロールしながら撮る 1 回ぶんの流れ
│   ├── ScrollStitcher        撮った画像をつなぐ
│   └── ScrollCapturePanel    操作パネルと点線の枠
├── Pin/            最前面に浮かぶウィンドウと、画像の表示・操作
│   ├── PinManager            浮かせている画像の一覧（閉じた画像を戻す・すべて閉じる・終了後も戻すための保存と復元 など）
│   ├── SavedPin・PinSessionStore  終了・再起動のあとも戻す状態（テストあり）と、その保存先（~/Library/Application Support/Pinshot/Pins に PNG と session.json）
│   ├── PinController(+◯◯)    画像 1 枚ぶんの操作（拡大縮小・不透明度・編集モード）。+Export はコピー・保存、+Menu は右クリックメニュー
│   ├── PinToolbarController  編集ツールバーのウィンドウ（出す・置く場所・説明のポップアップ）
│   ├── PinCanvasView(+◯◯)    画像と書き込みの表示と操作。役割ごとにファイルを分けている
│   │                         （+Cursor・+Mouse・+Keyboard・+Selection・+History・+Text・+Outside）
│   ├── PinAccessory          部品を画像の外に出す子ウィンドウ（操作バーはいつも。ほかは画像が小さくて中に入らないとき）
│   └── PinBackdropView・QuickActionBar・HUDView・HintBubble など   画像のまわりの部品
├── History/        撮った画像の履歴
│   ├── CaptureHistoryEntry   履歴の 1 枚と、残し方（期間・枚数）・日付ごとのまとめ方の決まり（テストあり）
│   ├── CaptureHistory        履歴の保存と読み込み（~/Library/Application Support/Pinshot/History に PNG・縮小画像・一覧の JSON）
│   └── CaptureHistoryWindowController・CaptureHistoryViewModel・CaptureHistoryView   一覧のウィンドウ（複数選択・浮かせる・コピー・保存・消す）
├── Editor/         書き込みのデータ、描画、書き出し
│   ├── Annotation・AnnotationStyles・Tool・RGBAColor   書き込みのデータ（Windows 版と形式をそろえる）
│   ├── AnnotationRenderer・ImageEffects・ImageExporter 描画・モザイクとぼかし・書き出し
│   ├── AnnotationDocument    1 枚の画像の編集データ（書き込み・トリミング・元に戻す履歴）。変えるときは必ずここを通す
│   ├── EditorState・EditorStyle・StylePreset・EditHistory  編集の状態・スタイルの保存・元に戻す
│   └── Toolbar/              ツールバー（SwiftUI）と、その部品・入力欄・カラーパネル
├── Assets.xcassets/ アプリのアイコン（scripts/make-app-icon.swift で描いて書き出す）
├── Settings/       設定の値（AppSettings・Shortcut・ExportDecoration）と画面
│   ├── SettingsWindowController  設定のウィンドウ（タブ）
│   ├── General・Pin・Export・History・ShortcutSettingsView   タブごとの画面
│   └── WelcomeView           初回の案内
└── Support/        どこからも使う部品
    ├── OverlayPanel          枠のない、前面を奪わないパネルの土台
    ├── PopupMenu             項目の並びからメニューを作る
    ├── ScreenGeometry        画面の座標の変換・ツールバーと操作バーを画像の下に置く位置
    ├── Permissions           画面収録・アクセシビリティの許可
    ├── GraphicsHelpers       画像の描き先を作る
    ├── HoverCursor           部品の種類（押せる・動かせる・操作できない）で決めるカーソル
    ├── ImageSaver            PNG を設定に合わせて保存する（浮かせた画像と履歴から使う）
    ├── AppFolders            アプリのデータを置くフォルダ（履歴・浮かせていた画像）
    └── ViewHelpers           前に出ていなくても押せるビュー・マウスの追跡

PinshotTests/       画面に関係ない処理のテスト（make test）
```

## 設計のメモ

- 書き込みの座標は「元の画像のポイント座標（左上が原点）」で持ち、拡大縮小・トリミングしても変わらない
- 書き込み・トリミング・元に戻す履歴は `AnnotationDocument` が持つ。変更は必ずそのメソッドを通し、「元に戻すに積む」「番号を詰める」などの決まりをそこで守る
- 浮かせた画像やツールバーは、クリックしても前面を奪わないパネル（`OverlayPanel`）で作る。アプリ全体を前に出すと、ほかの浮かせた画像まで前に出てしまうため
- テスト（`PinshotTests/`）は、アプリを起動せずに動く。画面に関係ないソースを、テストのターゲットに直接入れている（`project.yml`）
