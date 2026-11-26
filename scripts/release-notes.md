## ダウンロードと開き方

1. 下の `Pinshot-<版>.dmg` をダウンロードして開き、`Pinshot` を `Applications`（アプリケーションフォルダ）へドラッグします（`.zip` は展開して `Pinshot.app` を入れる形です。中身は同じ）
2. Pinshot を開くと「開発元を確認できない」と止められます（Apple の公証を受けていないため）。次のどれかで開けます
   - **macOS 15 以降**：システム設定 →「プライバシーとセキュリティ」の下の方にある「このまま開く」を押す
   - **macOS 14**：Pinshot を右クリック（control + クリック）して「開く」を選ぶ
   - **ターミナル**：`xattr -dr com.apple.quarantine /Applications/Pinshot.app` を実行してから開く
3. 初めてキャプチャするときに「画面収録」の許可を求められます。システム設定で Pinshot をオンにして、Pinshot を開き直してください
   - 録画にマイクの音を入れるときは、初めてのときに「マイク」の許可も求められます（使わなければ不要です）

入れたあとは、アプリの中から新しい版に更新できます（メニューバーのアイコン →「アップデートを確認…」。自動でも確かめます）。更新のときは、手順 2 も、許可の取り直しも要りません。0.4.1 までの版から上げるときだけ、もう一度ここからダウンロードして入れ替え、画面収録の許可を取り直してください（システム設定の一覧で古い Pinshot を「−」で消してから、もう一度許可します）。

ソースからビルドする方法は [README](https://github.com/yzanbo/pinshot#readme) を見てください。

---

**English:** Download the dmg (or zip), drag `Pinshot.app` to Applications, then allow it in System Settings → Privacy & Security ("Open Anyway"), or run `xattr -dr com.apple.quarantine /Applications/Pinshot.app`. The app is signed with the author's self-signed certificate and is not notarized. Once installed, it updates itself from the menu bar ("アップデートを確認…") and keeps its permissions across updates; when coming from 0.4.1 or earlier, install manually once more and grant Screen Recording permission again.
