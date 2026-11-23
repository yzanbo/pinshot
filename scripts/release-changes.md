## この版の主な変更（0.2.0-beta.1 から）

### 新しく使えるようになったこと

- **録画を GIF にして共有リンクに**：録画を止めたあとの窓の操作バーの 🔗（リンク）で、録画を GIF にして Gyazo に上げ、リンクをクリップボードに入れます。Slack・Discord・GitHub などに貼ると、その場で動く画像が出ます
  - GIF が大きいとき（10 MB を超えたとき・Gyazo に「大きすぎる」と断られたとき）は、大きさとコマの数を減らして作り直してから上げます。いちばん小さくしても上げられないときは、そう知らせます（録画を短くするか、範囲を小さくして録り直してください）
  - 動画（MP4）のままでは上げません（Gyazo の MP4 は有料プランだけのため）

**English:** New — share a screen recording as a GIF link: the link button in the recording window converts the recording to a GIF, uploads it to Gyazo, and copies the link. Large GIFs are automatically re-made smaller (size and frame rate) before uploading.
