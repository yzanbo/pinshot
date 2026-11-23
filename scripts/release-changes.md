## この版の主な変更（0.3.0-beta.1 から）

### 新しく使えるようになったこと

- **録画に音を入れる**：録画の音を「音なし・Mac の音・マイクの音・Mac の音＋マイクの音」から選べます（初めは音なし。選んだものは次の録画でも使います）
  - 選ぶ所は、範囲を選ぶ画面の下のバーの「録画」のすぐ右にある「録画の音」のボタン（押すと 4 つの選択肢が出ます）と、メニューバーの「録画」の下の「録画の音」です
  - Mac の音は、アプリや動画など Mac から出る音です（Pinshot 自身の音は入りません）。マイクの音は、自分の声などです。初めてマイクの音を入れて録画するときに、「マイク」の許可を求められます
  - 両方を選んだときは、止めたあとに 1 つの音にまとめます（Slack やブラウザでも、両方の音が鳴ります）
  - 録画を止めたあとの窓の操作バーに、音を出す・消すボタンを足しました（開いたときは音を消してあります）
  - GIF には音は入りません

### 変わったこと

- **Mac の容量を圧迫しないように**
  - 録画に「容量」の上限を足しました（設定の「履歴」の録画の行。合計 2／5／10／20 GB まで、初期値 5 GB）。超えたら古い録画から削除します（いちばん新しい録画と、浮かせて再生している録画は残します）
  - 上げたものの一覧は、新しい 1000 件まで残すようにしました。超えた古いものは一覧から外します（Gyazo からは消えません）

**English:** New — record audio with screen recordings: choose None, Mac audio, Microphone, or Mac audio + Microphone from the button next to "Record" in the capture bar, or from the menu bar. Both sources are mixed into a single track. The recording window has a new mute/unmute button. GIFs have no audio. Microphone permission is requested the first time you record with the microphone. Changed — to save disk space, recordings now have a total size limit (Settings → History, default 5 GB; oldest are removed first), and the upload history keeps the newest 1,000 entries (removed entries stay on Gyazo).
