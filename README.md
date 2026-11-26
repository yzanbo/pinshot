<p align="center">
  <img src="Pinshot/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Pinshot のアイコン">
</p>

<h1 align="center">Pinshot</h1>

<p align="center">
  画面をキャプチャして、そのまま最前面に浮かべておける macOS のメニューバーアプリ
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-PolyForm%20Shield%201.0.0-blue.svg" alt="PolyForm Shield License 1.0.0"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-lightgrey.svg" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5-orange.svg" alt="Swift 5">
</p>

<p align="center">
  <img src="docs/images/hero.png" width="760" alt="Pinshot で書き込みを入れて書き出した画像の例。設定画面の見本に、番号・モザイク・蛍光ペン・四角・矢印・文字を入れ、背景と影を付けている">
</p>

> [!NOTE]
> **いまは β 版です。** 思わぬ不具合があるかもしれません。見つけたら [Issues](https://github.com/yzanbo/pinshot/issues) で教えてください。操作や設定の保存形式は、正式版までに変わることがあります。

> **English:** Pinshot is a macOS menu bar app that captures part of your screen and keeps it floating above other windows. You can annotate the floating image with arrows, text, numbered markers, mosaic, and more, then copy or save it. The UI is currently in Japanese.

## できること

- **キャプチャ**：範囲・ウィンドウ・画面全体・タイマー。グローバルショートカット（初期設定は `⌘⇧2`）で始められます
- **画面の録画**：範囲・ウィンドウ・画面全体を録画し、浮かせてその場で再生できます。MP4 か GIF で保存・コピーできます（最長 10 分）。音は「音なし・Mac の音・マイクの音・Mac の音＋マイクの音」から選べます（GIF には音は入りません）
- **最前面に浮かべる**：撮った画像はその場に浮かび、ほかのアプリを使っている間も見えたままです。拡大縮小・不透明度も変えられます。終了・再起動しても、書き込みごと元の場所に戻ります
- **書き込み**：四角・楕円・矢印・ペン・蛍光ペン・文字マーカー（画像の文字に合わせて蛍光ペン・下線・取り消し線・囲み）・文字・番号・スポットライト・モザイク・ぼかし・トリミング。元に戻す・やり直す、スタイルの保存もできます
- **書き出し**：コピー・PNG で保存・ドラッグ＆ドロップ。余白・背景色・角丸・影を付けた見た目でも書き出せます
- **文字の読み取り**：浮かせた画像の文字を読み取ってコピーできます（全体か、ドラッグで選んだ範囲。日本語と英語。Mac の中で読み、ネットには送りません）。読み取った文字は吹き出しで見られ、直してからコピーし直すこともできます
- **共有リンク**：浮かせた画像を Gyazo に上げて、リンクをクリップボードに入れます（ページの URL・画像の URL・Markdown から選べます）。Slack・Discord・GitHub などに貼ると、その場で画像が出ます。撮ったら自動で上げることもできます（初期設定はオフ）。録画は GIF にして上げられます
- **履歴**：撮った画像と読み取った文字を、日付ごとに一覧で見られます。画像はもう一度浮かせたり、コピー・保存したり、文字はもう一度コピーしたりできます（残す期間と数は設定で選べます）。上げたもの（共有リンク）も一覧で見て、リンクのコピーや削除ができます
- **複数のディスプレイ**にも対応しています

くわしい操作は [docs/USAGE.md](docs/USAGE.md) を見てください。

## 使い方

1. **撮る**：`⌘⇧2` を押して、撮りたい範囲をドラッグします（`space` でウィンドウを撮るモードに切り替わります）。撮った画像は、その場に最前面で浮かびます
2. **書き込む**：画像をダブルクリックするか、画像の下の操作バーの「編集」で編集モードに入ります。番号・モザイク・文字マーカー・四角・矢印・文字などを重ねられます

   <p align="center">
     <img src="docs/images/annotate.gif" width="640" alt="番号、メールアドレスを隠すモザイク、注意書きの蛍光ペン、ボタンを囲む四角、矢印と文字を、1 つずつ書き込んでいく様子">
   </p>

3. **書き出す**：`⌘C` でコピー、`⌘S` で保存します。`⌥` を押しながらドラッグすると、ほかのアプリや Finder に直接ドロップできます。ツールバーの「背景」で、余白・背景・角丸・影を付けた見た目にもできます

見せたくないところはぼかしやモザイクで隠し、見せたいところはスポットライトで目立たせられます。

<p align="center">
  <img src="docs/images/focus.png" width="640" alt="名前とメールアドレスをぼかし、写真のところだけをスポットライトで明るくして、ラベルと矢印で示した例">
</p>

> この節の画像は、架空の画面に、Pinshot と同じ描き方で書き込みを入れて作った見本です（`make readme-images` で作り直せます）。

## ダウンロード

[Releases](https://github.com/yzanbo/pinshot/releases) から `Pinshot-<版>.dmg` をダウンロードして開き、`Pinshot` を `Applications`（アプリケーションフォルダ）へドラッグしてください（`.zip` もあります。展開して `Pinshot.app` を入れる形で、中身は同じです）。Intel と Apple Silicon のどちらの Mac でも動きます。

Apple の公証を受けていない（アドホック署名の）アプリなので、初めて開くときに「開発元を確認できない」と止められます。次のどれかで開けます。

- **macOS 15 以降**：一度開こうとしたあと、システム設定 →「プライバシーとセキュリティ」の下の方にある「このまま開く」を押す
- **macOS 14**：Pinshot を右クリック（control + クリック）して「開く」を選ぶ
- **ターミナル**：`xattr -dr com.apple.quarantine /Applications/Pinshot.app` を実行してから開く

初めてキャプチャするときに「画面収録」の許可を求められます。システム設定で Pinshot をオンにして、Pinshot を開き直してください。新しい版に入れ替えたときは、別のアプリと見なされるため、許可を取り直す必要があります（システム設定の一覧で古い Pinshot を「−」で削除してから、もう一度許可してください）。

## ソースからビルド

自分でビルドする場合の手順です。自分の Mac でビルドしたアプリは、「開発元を確認できない」という警告が出ません。

### 用意するもの

- macOS 14 以降
- Xcode 16 以降（App Store から入れる。コマンドラインツールだけではビルドできません）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### 手順

```bash
brew install xcodegen
git clone https://github.com/yzanbo/pinshot.git
cd pinshot
make install
```

`make install` は配布用（Release）にビルドし、`/Applications/Pinshot.app` に入れます。Intel と Apple Silicon のどちらの Mac でも動きます。終わったら、アプリケーションフォルダから Pinshot を開いてください。自分の Mac でビルドしたアプリなので、「開発元を確認できない」という警告は出ません。

初めてキャプチャするときに「画面収録」の許可を求められます。システム設定で Pinshot をオンにして、Pinshot を開き直してください。

### 新しい版にする

```bash
cd pinshot
git pull
make install
```

署名なし（アドホック署名）でビルドしているため、新しい版を入れると macOS から別のアプリと見なされ、画面収録の許可を取り直す必要があります。システム設定の画面収録の一覧で、古い Pinshot を「−」で削除してから、もう一度許可してください。何度もビルドし直す場合は、下の `make cert` を使うと、許可が外れなくなります。

### 削除

```bash
make uninstall
```

## 開発するとき

| コマンド | 内容 |
|---|---|
| `make cert` | 開発用の署名の証明書「Pinshot Dev」を作る（最初に一度だけ。任意） |
| `make run` | 動いている Pinshot を終了し、開発用（Debug）にビルドして起動する |
| `make build` | 開発用にビルドするだけ |
| `make test` | テストを動かす（アプリは起動しない） |
| `make install` | 配布用にビルドして `/Applications` に入れる |
| `make dist` | Releases に置く DMG と zip（`dist/Pinshot-<版>.dmg`・`.zip`）を作る（アドホック署名） |
| `make publish` | DMG と zip を作り、GitHub に Release（タグ `v<版>`）を作ってアップロードする。β 版は `make publish BETA=1`（タグ `v<版>-beta.1`・プレリリース） |
| `make stop` | 動いている Pinshot を終了する |
| `make generate` | `Pinshot.xcodeproj` を作るだけ（Xcode で開くとき） |
| `make icon` | アプリのアイコンを描き直す（`scripts/make-app-icon.swift` を変えたとき） |
| `make readme-images` | README の見本の画像（`docs/images`）を作り直す（`PinshotTests/ReadmeImages.swift`。書き込みの見た目を変えたとき） |

`Pinshot.xcodeproj` は `project.yml` から作るため、リポジトリには入れていません。

### `make cert` について

macOS は、画面収録の許可をアプリの署名にひも付けて覚えます。アドホック署名だと、ビルドし直すたびに別のアプリと見なされ、許可が外れます。`make cert` は自己署名の証明書「Pinshot Dev」をログインキーチェーンに作り（途中でパスワードを聞かれます）、以後の `make run`・`make install` はそれで署名します（[scripts/create-dev-cert.sh](scripts/create-dev-cert.sh)）。

許可しているのに案内の画面が出続けるときは、システム設定の画面収録の一覧から古い Pinshot を「−」で削除し、Pinshot を開き直してから許可し直してください。

## 必要な許可とプライバシー

| 許可 | 使う場面 |
|---|---|
| 画面収録 | 画面を撮るのに必要です。初めてキャプチャするときに求められます |
| アクセシビリティ（任意） | メニューを開いたままショートカットで撮るのに使います。許可しなくても、ほかの使い方はすべてできます |
| マイク（任意） | 録画の音にマイクの音を入れて、自分の声を録るときに使います。初めてマイクの音を入れて録画するときに求められます |

- Pinshot がネットワークに接続するのは、共有リンクを使うときだけです。設定の「共有」で上げる先（Gyazo）につなぎ、上げる操作をしたとき（自動で上げる設定なら、撮ったとき）に、その画像をあなたの Gyazo のアカウントへ直接送ります。Pinshot の作者のサーバーは通りません。上げる先につないでいなければ、ネットワークには接続しません
- Gyazo には、あなたが自分の Gyazo に登録したアプリのアクセストークンでつなぎます。トークンはこの Mac のキーチェーンに保存し、ほかには送りません。上げたものの一覧（リンクと小さな縮小画像）は `~/Library/Application Support/Pinshot/Uploads` に置きます（画像そのものは Gyazo にあり、一覧から外しても Gyazo からは消えません。消すときは「Gyazo からも削除」を選びます）。一覧は新しい 1000 件まで残し、超えた古いものは一覧から外します（Gyazo からは消えません）
- 浮かせている画像と閉じた画像（最大 10 枚）は、終了・再起動のあとも戻せるよう `~/Library/Application Support/Pinshot/Pins` に PNG と状態（書き込み・位置など）で残します。設定の「画像」で戻さないようにすると、すぐ削除します
- 撮った画像は、履歴として `~/Library/Application Support/Pinshot/History` に PNG で残します。読み取った文字も、読み取った範囲の画像と一緒に同じフォルダに残します（初期設定はどちらも 30 日・100 件まで。画像と文字で別々に決められます。期間を過ぎたもの・数を超えた古いものは自動で削除されます）。設定の「履歴」で、画像と文字それぞれ残さないようにしたり、すべて削除したりできます
- アクセシビリティを許可しているときは、メニューを開いている間もショートカットが効くよう、押したキーが割り当てたショートカットかどうかだけを確かめます。キーを記録したり、送ったりはしません
- 録画は、浮かせて再生できるよう `~/Library/Application Support/Pinshot/Recordings` に MP4 で残します。音を選んだときは、その音（Mac の音・マイクの音）も同じファイルに入れ、ほかには送りません（初期設定は 30 日・20 本・合計 5 GB まで。期間を過ぎたもの・数を超えた古いもの・合計が容量を超えた古いものは自動で削除されます）。保存した PNG・GIF・MP4 は、設定の「保存」の保存先（初期設定は `~/Pictures/Pinshot`。なければ作る。中を種類ごと・月ごとに分けることもできる）に置き、Pinshot が削除することはありません
- そのほかにファイルを書き出すのは、保存したときと、ほかのアプリへドラッグ＆ドロップしたとき（一時フォルダに PNG を置く）だけです
- 背景にいるときもカーソルの形を変えるために、macOS の公開されていない API（CoreGraphics の `SetsCursorInBackground`）を使っています。このため、Mac App Store では配布できません

## コードについて

- コードの構成と設計のメモ：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- テスト：`make test`（書き込みのデータ・元に戻す・書き出し・録画の決まりなど、画面に関係ない処理）

不具合の報告や提案は [Issues](https://github.com/yzanbo/pinshot/issues) へどうぞ。

## ライセンス

[PolyForm Shield License 1.0.0](LICENSE)

Pinshot のソースコードは公開していますが、オープンソースのライセンスではありません。使う・改変する・配ることはできますが、Pinshot と競合する製品（または、作者が Pinshot を使って提供する製品と競合する製品）を提供するために使うことはできません。正確な条件は、[ライセンスの本文](LICENSE)（英語）を見てください。
