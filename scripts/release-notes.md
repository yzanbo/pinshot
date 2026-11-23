## ダウンロードと開き方

1. 下の `Pinshot-<版>.dmg` をダウンロードして開き、`Pinshot` を `Applications`（アプリケーションフォルダ）へドラッグします（`.zip` は展開して `Pinshot.app` を入れる形です。中身は同じ）
2. Pinshot を開くと「開発元を確認できない」と止められます（Apple の公証を受けていないため）。次のどれかで開けます
   - **macOS 15 以降**：システム設定 →「プライバシーとセキュリティ」の下の方にある「このまま開く」を押す
   - **macOS 14**：Pinshot を右クリック（control + クリック）して「開く」を選ぶ
   - **ターミナル**：`xattr -dr com.apple.quarantine /Applications/Pinshot.app` を実行してから開く
3. 初めてキャプチャするときに「画面収録」の許可を求められます。システム設定で Pinshot をオンにして、Pinshot を開き直してください
   - 録画にマイクの音を入れるときは、初めてのときに「マイク」の許可も求められます（使わなければ不要です）

新しい版に入れ替えたときは、画面収録の許可を取り直す必要があります（システム設定の一覧で古い Pinshot を「−」で消してから、もう一度許可してください）。

ソースからビルドする方法は [README](https://github.com/yzanbo/pinshot#readme) を見てください。

---

**English:** Download the dmg (or zip), drag `Pinshot.app` to Applications, then allow it in System Settings → Privacy & Security ("Open Anyway"), or run `xattr -dr com.apple.quarantine /Applications/Pinshot.app`. The app is ad-hoc signed and not notarized. You will need to grant Screen Recording permission again after each update.
