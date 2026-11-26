# コードの構成

```
Pinshot/
├── App/            起動と、アプリ全体に関わるもの
│   ├── AppDelegate           起動・グローバルショートカットの登録・更新の仕組みを始める・起動の記録（版と許可）
│   ├── AppActions            操作の入口（撮る・録る・浮かせる・履歴を開くなど）。ショートカットとメニューバーのメニューは、どちらもここを呼ぶ
│   ├── HotKey・ShortcutKeyTap  グローバルショートカット（Carbon）と、メニューを開いている間もショートカットを受けるキーの見張り
│   ├── StatusMenuController  メニューバーのアイコン（録画中・アップロード中・新しい版があるときで変える）とメニュー
│   ├── MenuBarIcon           メニューバーのカメラのアイコンと、新しい版があるときの印入りのもの（右下に下向きの矢印の丸。1 色）
│   ├── AppUpdates            更新の状態（使えるか・自動で確かめるか・知らせる新しい版）。更新そのものは AppUpdateService（アプリでは SparkleUpdater）が受け持つ（テストあり）
│   ├── SparkleUpdater        更新（Sparkle）。新しい版を確かめる・知らせる・入れ替える。Sparkle を読み込むのは、このファイルだけ
│   ├── DockIcon              設定・履歴などのウィンドウ（と Sparkle の更新の画面）を開いている間だけ、Dock にアイコンを出す
│   ├── AppInfo               記録（Logger の subsystem）と、版・ビルド番号の読み出し
│   └── AppSupport・AppRelauncher  メインメニュー・アプリのアイコン・⌘Q の扱い、起動し直し
├── Screenshot/     画面の撮影（ScreenCaptureKit）と範囲の選択
│   ├── CaptureController     撮る流れ（選ぶ → タイマー → 浮かせる）
│   ├── ScreenCapturer・WindowList  画面・ウィンドウを撮る、画面に出ているウィンドウの一覧
│   ├── CaptureTypes          モード・撮るもの・撮った画面などの型
│   ├── CaptureShield         ショートカットを押した瞬間に画面にかぶせる透明なウィンドウ（そのまま範囲を選ぶ画面になる）
│   ├── SelectionController   範囲を選ぶ画面（画面ごとのウィンドウ・モードの切り替え）
│   ├── SelectionView(+Drawing)  選ぶ操作（マウス）と、範囲・ルーペ・座標の描画
│   ├── CaptureModeBar・CountdownPanel  モードとタイマーを選ぶバー（SwiftUI）、タイマーの秒読み
│   └── CaptureCursors        キャプチャ中のカーソル
├── Recording/      画面の録画
│   ├── RecordingRules        録画の決まり（大きさを偶数に・座標・時間の表示・ファイル名・GIF のコマ数と大きさ・古い録画の整理・録画の音の選択肢 RecordingAudio。テストあり）
│   ├── ScreenRecorder        画面（と Mac の音・マイクの音）を受け取って MP4 に書く（ScreenCaptureKit の SCStream → AVAssetWriter。両方の音のときは、止めたあとに AudioMixdown で 1 本に混ぜる）
│   ├── RecordingController   録画を始める・止める入口（赤い点線の枠・操作パネル・上限）
│   ├── RecordingStore        アプリの中に残す録画（期間・数・容量の上限で古いものを削除・本数と容量）
│   ├── RecordingPlayer       録画を浮かせてくり返し再生する窓（見た目は浮かせた画像にそろえる：左上の外の ×・下の操作バーと左端の ✙。再生・一時停止・位置のつまみ・音を出す / 消す | コピー・GIF にして上げる | MP4 / GIF で保存・Finder で表示）
│   ├── MicrophoneCapture     マイクの音を受け取る（AVCaptureSession。時刻を画面のコマと同じホストの時計に直す）
│   ├── AudioMixdown          Mac の音とマイクの 2 本の音を 1 本に混ぜて書き直す（映像はそのまま。テストあり）
│   ├── GIFExporter           録画から GIF を作る（テストあり）
│   └── CaptureOutline        録画している範囲の外側の赤い点線の枠（録画には写らない）
├── Pin/            最前面に浮かぶウィンドウと、画像の表示・操作
│   ├── PinManager            浮かせている画像の一覧（閉じた画像を戻す・すべて閉じる・終了後も戻すための保存と復元 など）
│   ├── SavedPin・PinSessionStore  終了・再起動のあとも戻す状態（1 枚ずつ読む・形の番号。テストあり）と、その保存先（~/Library/Application Support/Pinshot/Pins に PNG と session.json。読めないところがあれば unreadable-日時 のフォルダに残す）
│   ├── PinController(+◯◯)    画像 1 枚ぶんの操作（拡大縮小・不透明度・編集モード）。+Export はコピー・保存、+Menu は右クリックメニュー
│   ├── PinPanel・PinAppearance  画像のウィンドウ、画像の不透明度と拡大率（操作バーとツールバーで同じ値を見る）
│   ├── PinToolbarController  編集ツールバーのウィンドウ（出す・置く場所・つまみで動かす）
│   ├── PinCanvasView(+◯◯)    画像と書き込みの表示と操作。役割ごとにファイルを分けている
│   │                         （+Cursor・+Mouse・+Keyboard・+Selection・+History・+Text・+TextRecognition・+TextMark・+Outside）
│   ├── PinAccessory          部品を画像の外に出す子ウィンドウ（閉じるボタンと操作バーはいつも。ほかは画像が小さくて中に入らないとき）
│   ├── PinBackdropView       画像のまわりの背景（余白・影）
│   ├── QuickActionBar・PinCloseButton  画像の下の操作バー（編集中はツールバーの上のバーとしても使う）と選んだ書き込みのバー、左上の外の閉じるボタン
│   ├── HUDView・HintBubble   「コピーしました」などのお知らせ、ボタンの説明のポップアップ（HoverHints。Pinshot が前面になくても出る。操作バー・編集ツールバー・録画の窓など、どのバーも .hoverHint で出す）
│   ├── TextScanOverlay・RecognizedTextPopover  文字を読み取っている間・読み取ったあとの見た目と、読み取った文字の吹き出し（直してコピーし直せる）
│   └── ResizeEdges           端のドラッグで大きさを変える計算（テストあり）
├── Upload/         アップロードして共有リンク（いまは Gyazo。ほかの保存先を足せるように分けてある）
│   ├── UploadTypes・UploadRules  保存先の種類・できること・上げたファイル・共有リンク・コピーする形・失敗の知らせ、コピーする文・ファイル名・トークンらしさ・multipart の本文（テストあり）
│   ├── UploadDestination     保存先の protocol（上げる・共有リンク・消す・ログアウト）と、使える保存先の一覧
│   ├── UploadCenter          どの保存先でも同じ流れ（上げる → リンク → コピー → 履歴 → 知らせる・進み具合・自動で上げる）と、録画を GIF にして上げる流れ（大きすぎたら小さく作り直す）
│   ├── UploadHistoryEntry・UploadHistory  上げたものの 1 件と決まり（テストあり）、その保存（~/Library/Application Support/Pinshot/Uploads に一覧の JSON と縮小画像。新しい 1000 件まで）
│   ├── UploadHTTP・UploadNotifier  通信と返事の番号の読み替え・送った割合、macOS の通知
│   ├── Destinations/GyazoDestination  Gyazo（利用者が貼ったアクセストークンで上げる・消す）
│   └── OAuth/                OAuth 2.0 の共通の部品（PKCE・ログインの画面・localhost の受け口・許可証の取り直し・キーチェーン）。いまは使う保存先がないが、ほかの保存先を足すときに使う（テストあり）
├── History/        撮った画像・読み取った文字・上げたものの履歴
│   ├── CaptureHistoryEntry   履歴の 1 枚と、残し方（期間・数）・日付ごとのまとめ方・表示の文字の決まり（テストあり）。期間と日付は文字の履歴にも使う
│   ├── CaptureHistory        画像の履歴の保存と読み込み（~/Library/Application Support/Pinshot/History に PNG・縮小画像・一覧の JSON）
│   ├── TextHistoryEntry・TextHistory  読み取った文字の履歴の 1 件と決まり（同じ文字はまとめる・探す。テストあり）と、その保存（同じフォルダに texts.json と、読み取った範囲の画像）
│   ├── ListSelection         一覧の選び方（クリック・⌘・shift・⌘A・矢印）と、キー操作の決まり（ListKeys）。画像・文字・共有の一覧で同じ（テストあり）
│   ├── CaptureHistoryWindowController・HistoryWindowView  履歴のウィンドウ（開くときに編集中の画像の編集を終える・キー操作の振り分け）と、その中身（上の「画像 / 文字 / 共有」の切り替え・表示方法・探す欄）
│   ├── CaptureHistoryViewModel・CaptureHistoryView  画像の一覧（複数選択・浮かせる・コピー・保存・消す）
│   ├── TextHistoryViewModel・TextHistoryView  文字の一覧と右の全文の欄（探す・複数選択・コピー・消す・直す・読み取った画像を浮かせる）
│   ├── UploadHistoryViewModel・UploadHistoryView  上げたものの一覧（撮った画像と同じ 3 つの表示・複数選択・リンクをコピー・ブラウザで開く・Gyazo からも削除）
│   ├── HistoryComponents     画像・文字・共有の一覧で同じ部品（日付ごとの並べ方（サムネイル・リスト）・日付の見出し・空のときの案内・小さな画像・サムネイルの 1 件と列・行の背景・乗せたときのボタン・下の帯）
│   └── HistoryNotice         一覧の下に出す短い知らせ（「コピーしました」など。アップロードの途中は消さずに出す）
├── Editor/         書き込みのデータ、描画、書き出し
│   ├── Annotation・AnnotationStyles・Tool・ToolGroup・RGBAColor   書き込みのデータ（Windows 版と形式をそろえる）と、ツールの組
│   ├── AnnotationRenderer・ImageEffects・ImageExporter 描画・モザイクとぼかし・書き出し
│   ├── TextRecognizer        文字の読み取り（Vision）と、読み取った文字を読む順に並べる決まり（テストあり）
│   ├── TextMarkLayout        文字マーカーを、ドラッグした所の文字に合わせて行ごとの四角にする決まりと、その形・画素を見て文字の線がある高さに合わせる処理（TextInk）（テストあり）
│   ├── AnnotationDocument    1 枚の画像の編集データ（書き込み・トリミング・元に戻す履歴）。変えるときは必ずここを通す
│   ├── EditHandle            選んだ書き込みのつまみ（形を直す）
│   ├── EditorState・EditorStyle・StylePreset・EditHistory  編集の状態・スタイルの保存・元に戻す
│   └── Toolbar/              ツールバー（SwiftUI）と、その部品
│       ├── EditorToolbar(+Options)・ToolbarComponents・ToolbarMenuButtons  ツールバー本体（+Options は 2 行目のツールごとのオプション）、共通の部品、メニューを開くボタン
│       ├── TextStylePreview  文字ツールのオプションの見本（書き込みと同じ描き方で、次に入力する文字の見え方を出す）
│       ├── ViewControls      不透明度と拡大率（操作バーに出す。編集中もツールバーの上のバーとして同じ操作バーを出す）
│       └── FontMenu・TextInputController・ColorPanelController  フォントのメニュー、数字や名前の入力欄、カラーパネル
├── Assets.xcassets/ アプリのアイコン（scripts/make-app-icon.swift で描いて書き出す）
├── Licenses/       アプリに同梱するライセンス（Sparkle.txt。make が、取り寄せた Sparkle の配布物から写す）
├── Settings/       設定の値（AppSettings・Shortcut・ExportDecoration）と画面
│   ├── SettingsWindowController  設定のウィンドウ（タブ）
│   ├── General・Pin・Export・History・Share・ShortcutSettingsView   タブごとの画面
│   ├── GyazoSetupView        Gyazo につなぐまでの案内の窓（アプリの登録 → トークンを作る → 貼ってつなぐ）
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
    ├── AppFolders            アプリのデータを置くフォルダ（履歴・浮かせていた画像・録画・上げたもの。更新の試験用アプリは、Info.plist の PinshotDataFolderName で別のフォルダ）
    ├── StoredJSON            そのフォルダに置く一覧の JSON の読み書き（1 件ずつ読み、読めないものだけ飛ばす。そのときは元のファイルを別名で残し、上書きで失わない。テストあり）
    ├── SaveLocation          保存したもの（画像・GIF・動画）を置く場所の決まり（保存先の中を種類ごと・月ごとに分ける。テストあり）
    └── ViewHelpers           前に出ていなくても押せるビュー・マウスの追跡・角の丸い枠（framedBox）・ドラッグで窓を動かす所（WindowDragArea）

PinshotTests/       画面に関係ない処理のテスト（make test）

scripts/            ビルドと配る手順の道具（Makefile から使う）
├── create-dev-cert.sh       署名の証明書「Pinshot Dev」を作る（make cert。配る版の署名にも使うので、作るのは最初の 1 回だけ）
├── signing-check.sh         配る版の証明書（SHA-1）が、ビルドの前にこの Mac にあるか・ビルドのあとにそれで署名されたかを確かめる（make dist・make update-test）
├── update-key.sh            更新ファイルの署名の鍵（EdDSA）を用意して、公開鍵を project.yml に書き込む（make update-key）
├── make-appcast.sh          更新ファイル（zip）に署名して、版の一覧（appcast.xml）を作る（make publish・make update-test）
├── publish-check.sh         公開の前に、鍵と Git の状態・タグを確かめる（make publish）
├── update-test.sh           更新を手元で通しで試す準備をする（make update-test。update-test-key.swift は、その試験用の鍵を作る）
├── update-test-log.sh       更新の試験のあいだの macOS の記録を書き出す（make update-test-log）
├── make-app-icon.swift      アプリのアイコンをコードで描いて、Assets.xcassets に書き出す（make icon）
├── readme-images/           README の絵を作る（make readme-images）
└── release-*.md             リリースの説明（β 版の注意・この版の変更・ダウンロードと開き方。make publish がつなげる）

appcast.xml         版の一覧（入れてもらったアプリが、ここを見て新しい版を知る。make publish が作り直す）
Vendor/Sparkle/     更新の仕組み（Sparkle）の配布物。make が取り寄せるので、リポジトリには入れない
```

## 設計のメモ

- 書き込みの座標は「元の画像のポイント座標（左上が原点）」で持ち、拡大縮小・トリミングしても変わらない
- 書き込み・トリミング・元に戻す履歴は `AnnotationDocument` が持つ。変更は必ずそのメソッドを通し、「元に戻すに積む」「番号を詰める」などの決まりをそこで守る
- 浮かせた画像やツールバーは、クリックしても前面を奪わないパネル（`OverlayPanel`）で作る。アプリ全体を前に出すと、ほかの浮かせた画像まで前に出てしまうため
- カーソル（`HoverRole`）・キーの番号（`KeyCode`）・画面に収める位置（`ScreenGeometry`）・背景の描き方（`ExportDecoration`）・ダイアログ（`AppAlert`）は、部品ごとに直接書かず、共通の部品を使う
- テスト（`PinshotTests/`）は、アプリを起動せずに動く。画面に関係ないソースを、テストのターゲットに直接入れている（`project.yml`）
- 保存する形（書き込みの種類・項目の名前）を変えると、前の版が残したものを読めなくなる。`StoredFormatTests` に、いまの版が書いた JSON を決まった文字列で持っているので、形を変えるときは前の形を読み替えて引き継ぎ、そのテストの JSON は書き換えない（新しい形のテストを足す）。浮かせていた画像の形を前の版で読めないように変えたら、`SavedPinSession.currentVersion` を増やす

### 署名

- macOS は、画面収録・アクセシビリティ・マイクの許可を、アプリの「同じアプリ」の条件（designated requirement）にひも付けて覚える。アドホック署名は、条件が中身のハッシュなので、ビルドし直すたび・版が変わるたびに別のアプリと見なされ、許可が外れる。自己署名の証明書「Pinshot Dev」で署名すると、条件は「アプリの ID ＋ 証明書」になり、版が変わっても同じアプリと見なされる
- 開発のビルド（`make run`・`make install`）は、Pinshot Dev があればそれで署名する（なければアドホック署名）
- 配る版（`make dist`）は、いつも Pinshot Dev で署名する（0.5.0 から。0.4.1 まではアドホック署名だった）。Apple の公証ではないので、初めて開くときの「このまま開く」は残る
- 名前が同じでも、作り直した証明書は別物で、それで配ると、更新を入れた人の許可が外れる。そのため配る版は、証明書を名前ではなく SHA-1（`Makefile` の `RELEASE_SIGN_IDENTITY`）で選んで署名する（`make update-test` も同じ証明書で署名する）。作り直した証明書や、同じ名前の別の証明書では署名できない。ビルドの前に、その証明書があるか（なければ控えの取り込み方を出して止まる）、ビルドのあとに、その証明書で署名されたかも確かめる（`scripts/signing-check.sh`）
- 証明書の秘密鍵は作り直せない。キーチェーンアクセスで「Pinshot Dev」を選んで「書き出す…」で、強いパスワード付きの `.p12` にし、パスワード管理アプリなど Mac の外にも保管する。別の Mac でビルドするときは `make cert` で作らず、この控えを取り込み（ダブルクリック）、キーチェーンアクセスでその証明書の「信頼」→「コード署名」を「常に信頼」にする（`security find-identity -v -p codesigning` に出れば使える）
- 有効期限は 2036 年 11 月まで。切れる前に、Developer ID に移るか作り直すかを決める（どちらも、切り替える版で 1 回だけ別のアプリ扱いになる）
- Hardened Runtime は切っている（`ENABLE_HARDENED_RUNTIME = NO`）。埋め込んだ Sparkle は、Xcode が本体だけを Pinshot Dev で署名し直し、中の部品（`Autoupdate`・`Updater.app`・XPC サービス）は配布物のアドホック署名のまま。Hardened Runtime とライブラリの検証を使っていないので、このまま動く（`codesign --verify --deep --strict` も通る）
- 配る版（Release）には、デバッガをつなぐための許可（`get-task-allow`）を入れない（`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`。何もしないと、Xcode がビルドのときに足す。0.4.1 までの配布物には入っていた）

### 更新

Developer ID に登録しない前提で、[Sparkle](https://sparkle-project.org) 2 を使う（Pinshelf と同じ形。検討の経緯は、Pinshelf のノート「更新の仕組みの方針」にまとめてある）。

- **取り込み方**: 公式の配布物（`Sparkle.framework` と道具）を `make` が取り寄せ、決めてある SHA-256 と合うことを確かめて `Vendor/Sparkle` に置く。Swift パッケージにしないのは、取り寄せる版と中身を固定し、道具（`generate_appcast` など）も同じ配布物から使うため。Sparkle の版を上げるときは、`Makefile` の `SPARKLE_VERSION` と `SPARKLE_SHA256` を一緒に変える
- **本物かの確かめ**: 更新ファイル（zip）は、作者の EdDSA の鍵で署名する。アプリには公開鍵（`SUPublicEDKey`）を入れ、Sparkle が署名を確かめてから入れ替える。鍵は Pin シリーズで共通（Pinshelf と同じ鍵）。公開鍵の入っていないビルドでは、更新の機能を出さない（`SparkleUpdater.start` が nil を返す）
- **「このまま開く」が要らない理由**: Sparkle が自分でダウンロードして確かめた版からは、ダウンロードのしるし（quarantine）を外す。だから、更新で入れた版は Gatekeeper に止められない
- **許可が外れない理由**: どの版も同じ証明書で署名しているので（上の「署名」）、入れ替えた版も同じアプリと見なされる。リリースの前に `make update-test` で確かめる（docs/TESTING.md）
- **サンドボックス**: Pinshot は使っていないので、Sparkle の入れ替え役（XPC サービス）も、ネット接続などの許可（entitlements）も要らない（Pinshelf はサンドボックスのため、どちらも足している）
- **知らせ方**: メニューバーに常駐するアプリなので、自動で見つけた新しい版は画面に割り込ませず、アイコンの印とメニューで知らせる（Sparkle の「控えめな知らせ」の作法。`standardUserDriverShouldHandleShowingScheduledUpdate` で、いつも自分で受け持つ）。メニューから選ぶと、Sparkle の更新の画面が前面に出る。知らせの決まりは Pin シリーズ共通（Pinshelf のノート「更新の仕組みの方針」の 8 の節）
- **確かめる間隔**: 1 時間に 1 回（`SUScheduledCheckInterval` 3600。Sparkle が受け付けるいちばん短い間隔で、VS Code と同じ）。起動したときは、前に確かめてから 1 時間以上たっていれば、すぐ確かめる。版の一覧は小さな XML 1 つなので、1 時間ごとでも GitHub への負担は小さい
- **印の形**: カメラのアイコンの右下を丸く切り抜き、下向きの矢印を抜いた丸を置いたものに替える（`MenuBarIcon`）。テンプレート画像のままにして、色は付けない（メニューバーの色付きの点は、マイク・カメラの使用中の印と紛れやすい）。Pinshelf は丸を直径 10pt にしているが、Pinshot でそうするとカメラのレンズが欠けるので、直径 8.4pt にした（PNG に書き出して見比べた）。録画中・アップロード中は、それぞれのアイコンを出し、終わってから印入りに戻す
- **印を消すとき**: 印は「まだ入れていない新しい版がある」の意味で、入れるか飛ばすまで出しておく（VS Code・Chrome と同じ考え方）。Sparkle の説明書は「画面を見てもらったら印を消す」作り（`standardUserDriverDidReceiveUserAttention`）を勧めるが、それだと更新の画面を開いて「あとで通知」で閉じただけで消え、次に自動で確かめるまで戻らないので使わない。見つけた版とビルド番号を `UserDefaults` に保存し（`AppUpdates`）、起動したときに今の版より新しければ印を戻す（終了しても消えないように）。消すのは、利用者が「このバージョンはスキップ」を選んだとき（`updater(_:userDidMake:forUpdate:state:)` の `.skip`）・確かめ直して新しい版がなかったとき（`updaterDidNotFindUpdate`。通信の失敗では呼ばれない）・入れて今の版が同じか新しくなったとき。Sparkle の受け口は任意のメソッドで、Swift での名前を間違えてもエラーにならず呼ばれないだけなので、`#selector(SPUUpdaterDelegate.updater(_:userDidMake:forUpdate:state:))` のような型検査で確かめた
- **Dock**: 更新の画面は Sparkle のウィンドウで、開け閉めを自分では知れないので、確かめ始めてから確かめ終えるまで、名前付きの印で Dock に出しておく（`DockIcon.hold`・`release`）
- **確認中の小窓の長さ**: 問い合わせはすぐ終わり、「アップデートを確認中…」の小窓が一瞬で閉じてちらついて見えるので、Sparkle の標準の画面（`SPUStandardUserDriver`）を `PacedUserDriver` で包み、小窓を少なくとも 0.5 秒は出してから結果の画面に渡す（そのため `SPUStandardUpdaterController` ではなく、`SPUUpdater` を自分で作る）
- **画面の側との分け方**: Sparkle を読み込むのは `SparkleUpdater` だけ。メニューと設定は `AppUpdates`（状態）を通して使う。Sparkle なしでアプリのコードをビルドする `make readme-images` と、テストのため
- **版の一覧**: `appcast.xml` をリポジトリの main に置き、アプリは `raw.githubusercontent.com` から読む（β 版は GitHub の「最新の版」に出ないので、Releases の latest は使えない）。載せるのは、いちばん新しい版だけ。この版の変更（`scripts/release-changes.md`）を、Markdown のまま埋め込む
- **版の比べ方**: Sparkle は `CFBundleVersion`（ビルド番号）で新旧を比べる。出すたびに必ず上げる
- **記録**: 起動のたびに、版・画面収録とアクセシビリティの許可・「ログイン時に起動」を、macOS の記録に 1 行残す（`AppDelegate.logLaunch`。subsystem は `dev.portfolio.pinshot`）。入れ替えのあとに許可が引き継がれたかを、あとから確かめられる
- **試験用アプリ**: `make update-test` は、別の ID（`dev.portfolio.pinshot.UpdateTest`）・別の名前・別のデータのフォルダ（Info.plist の `PinshotDataFolderName`。`AppFolders`）で作る。サンドボックスがないので、データのフォルダを分けないと、ふだんの Pinshot の履歴・浮かせた画像を読み、試験用アプリの設定（残す期間・数）で消してしまう。Gyazo の許可証のキーチェーンの名前は、アプリの ID から作るので、試験用アプリでは自然に分かれる（`KeychainTokenStore`。配る Pinshot では、これまでと同じ名前）
- **ライセンス**: Sparkle のライセンス（MIT など）は、配るものに全文を含める決まり。`Pinshot/Licenses/Sparkle.txt` として同梱する（`make` が、取り寄せた配布物から写す）

### 版とリリース

- 版（`CFBundleShortVersionString`）とビルド番号（`CFBundleVersion`）は `project.yml` で決める。出すたびに両方を上げ、`scripts/release-changes.md`（この版の変更）を書き直す
- `make publish BETA=1` で β 版としてプレリリースにする（タグは `v<版>-beta.1`。説明の先頭に `scripts/release-notes-beta.md` の注意が付く）。正式版は `BETA` を付けずに `make publish`
- `make publish` は、先に証明書・鍵・Git の状態・タグを確かめ（`scripts/signing-check.sh`・`scripts/publish-check.sh`）、そろっていなければ何も作らずに止まる。Release を作る前に zip に署名して `appcast.xml` を作り直し、Release を作ったあと、`appcast.xml` だけをコミットしてプッシュする
- 更新ファイルの署名の鍵（EdDSA）の秘密鍵は、ログインキーチェーンにある（Pinshelf で `make update-key` を流したときに作ったもの）。失くすと更新を届けられなくなるので、控え（`Vendor/Sparkle/bin/generate_keys -x <ファイル>`）を安全な場所に保管する。別の Mac で公開するときは、控えを `generate_keys -f <ファイル>` で取り込み、証明書の控えも取り込む
- リリースの前に、`make update-test` で、更新しても許可が引き継がれることを確かめる（docs/TESTING.md）
