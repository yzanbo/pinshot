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

> [!NOTE]
> **いまは β 版です。** 思わぬ不具合があるかもしれません。見つけたら [Issues](https://github.com/yzanbo/pinshot/issues) で教えてください。操作や設定の保存形式は、正式版までに変わることがあります。

> **English:** Pinshot is a macOS menu bar app that captures part of your screen and keeps it floating above other windows. You can annotate the floating image with arrows, text, numbered markers, mosaic, and more, then copy or save it. The UI is currently in Japanese.

## できること

- **キャプチャ**：範囲・ウィンドウ・画面全体・タイマー。グローバルショートカット（初期設定は `⌘⇧2`）で始められます
- **スクロールキャプチャ**：ブラウザなどのページを自動でスクロールしながら撮り、1 枚の縦長の画像につなぎます
- **最前面に浮かべる**：撮った画像はその場に浮かび、ほかのアプリを使っている間も見えたままです。拡大縮小・不透明度・クリックの透過もできます
- **書き込み**：四角・楕円・矢印・ペン・蛍光ペン・文字・番号・スポットライト・モザイク・ぼかし・トリミング。元に戻す・やり直す、スタイルの保存もできます
- **書き出し**：コピー・PNG で保存・ドラッグ＆ドロップ。余白・背景色・角丸・影を付けた見た目でも書き出せます
- **撮った画像の履歴**：撮った画像を日付ごとに一覧で見て、もう一度浮かせたり、コピー・保存したりできます（残す期間と枚数は設定で選べます）
- **複数のディスプレイ**にも対応しています

くわしい操作は [docs/USAGE.md](docs/USAGE.md) を見てください。

## ダウンロード

[Releases](https://github.com/yzanbo/pinshot/releases) から `Pinshot-<版>.dmg` をダウンロードして開き、`Pinshot` を `Applications`（アプリケーションフォルダ）へドラッグしてください（`.zip` もあります。展開して `Pinshot.app` を入れる形で、中身は同じです）。Intel と Apple Silicon のどちらの Mac でも動きます。

Apple の公証を受けていない（アドホック署名の）アプリなので、初めて開くときに「開発元を確認できない」と止められます。次のどれかで開けます。

- **macOS 15 以降**：一度開こうとしたあと、システム設定 →「プライバシーとセキュリティ」の下の方にある「このまま開く」を押す
- **macOS 14**：Pinshot を右クリック（control + クリック）して「開く」を選ぶ
- **ターミナル**：`xattr -dr com.apple.quarantine /Applications/Pinshot.app` を実行してから開く

初めてキャプチャするときに「画面収録」の許可を求められます。システム設定で Pinshot をオンにして、Pinshot を開き直してください。新しい版に入れ替えたときは、別のアプリと見なされるため、許可を取り直す必要があります（システム設定の一覧で古い Pinshot を「−」で消してから、もう一度許可してください）。

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

署名なし（アドホック署名）でビルドしているため、新しい版を入れると macOS から別のアプリと見なされ、画面収録の許可を取り直す必要があります。システム設定の画面収録の一覧で、古い Pinshot を「−」で消してから、もう一度許可してください。何度もビルドし直す場合は、下の `make cert` を使うと、許可が外れなくなります。

### 消す

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

`Pinshot.xcodeproj` は `project.yml` から作るため、リポジトリには入れていません。

### `make cert` について

macOS は、画面収録の許可をアプリの署名にひも付けて覚えます。アドホック署名だと、ビルドし直すたびに別のアプリと見なされ、許可が外れます。`make cert` は自己署名の証明書「Pinshot Dev」をログインキーチェーンに作り（途中でパスワードを聞かれます）、以後の `make run`・`make install` はそれで署名します（[scripts/create-dev-cert.sh](scripts/create-dev-cert.sh)）。

許可しているのに案内の画面が出続けるときは、システム設定の画面収録の一覧から古い Pinshot を「−」で消し、Pinshot を開き直してから許可し直してください。

## 必要な許可とプライバシー

| 許可 | 使う場面 |
|---|---|
| 画面収録 | 画面を撮るのに必要です。初めてキャプチャするときに求められます |
| アクセシビリティ（任意） | スクロールキャプチャで、スクロールする部分を見つけて自動でスクロールするのと、メニューを開いたままショートカットで撮るのに使います。許可しなくても、自分でスクロールすれば撮れます |

- Pinshot はネットワークに接続しません。撮った画像は Mac の中だけで扱います
- 撮った画像は、履歴として `~/Library/Application Support/Pinshot/History` に PNG で残します（初期設定は 30 日・100 枚まで。期間を過ぎたもの・枚数を超えた古いものは自動で消えます）。設定の「履歴」で、残さないようにしたり、すべて消したりできます
- アクセシビリティを許可しているときは、メニューを開いている間もショートカットが効くよう、押したキーが割り当てたショートカットかどうかだけを確かめます。キーを記録したり、送ったりはしません
- そのほかにファイルを書き出すのは、保存したときと、ほかのアプリへドラッグ＆ドロップしたとき（一時フォルダに PNG を置く）だけです
- 背景にいるときもカーソルの形を変えるために、macOS の公開されていない API（CoreGraphics の `SetsCursorInBackground`）を使っています。このため、Mac App Store では配布できません

## コードについて

- コードの構成と設計のメモ：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- テスト：`make test`（書き込みのデータ・元に戻す・スクロールキャプチャのつなぎ合わせ・書き出しなど、画面に関係ない処理）

不具合の報告や提案は [Issues](https://github.com/yzanbo/pinshot/issues) へどうぞ。

## ライセンス

[PolyForm Shield License 1.0.0](LICENSE)

Pinshot のソースコードは公開していますが、オープンソースのライセンスではありません。使う・改変する・配ることはできますが、Pinshot と競合する製品（または、作者が Pinshot を使って提供する製品と競合する製品）を提供するために使うことはできません。正確な条件は、[ライセンスの本文](LICENSE)（英語）を見てください。
