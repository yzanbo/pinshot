#!/bin/bash
# 更新の試験（make update-test）のあいだの macOS の記録を、ファイルに書き出す（make update-test-log）。
#
# 試験用アプリと Sparkle の入れ替えの部品が出した記録に加えて、macOS の側（許可の確かめ・ログイン項目など）が
# 試験用アプリについて出した記録を集める。許可が引き継がれたかの裏取りと、うまくいかないときの手がかりに使う。
# 試験用アプリは、起動のたびに「版・画面収録とアクセシビリティの許可・ログイン時に起動」を 1 行残す（AppDelegate の logLaunch）。
#
# 使い方: update-test-log.sh
#   環境変数 SINCE: いつからの記録を集めるか（"2026-11-26 19:50:00" の形）。なければ、直近 30 分
#
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-signing-cert.sh と同じ理由）。
set -euo pipefail

OUTPUT="build/update-test/system.log"
mkdir -p "$(dirname "${OUTPUT}")"

# 集めるもの:
# - 試験用アプリの ID・名前・置き場所が出てくる記録（許可を確かめる tccd など、macOS の側が試験用アプリについて出したもの）
# - 試験用アプリと、その中の部品が出した記録（入れ替えの部品は、試験用アプリの ID の付いた場所に写して動く）
# - Sparkle の記録
PREDICATE='eventMessage CONTAINS "UpdateTest"
  OR eventMessage CONTAINS "update-test/"
  OR processImagePath CONTAINS "UpdateTest"
  OR processImagePath CONTAINS "update-test/"
  OR subsystem == "org.sparkle-project.Sparkle"'

if [ -n "${SINCE:-}" ]; then
  RANGE=(--start "${SINCE}")
else
  RANGE=(--last 30m)
fi

echo "記録を集めています（1 分ほどかかることがあります）…"
log show "${RANGE[@]}" --style compact --info --predicate "${PREDICATE}" > "${OUTPUT}"
echo "記録を書き出しました: ${OUTPUT}（$(wc -l < "${OUTPUT}" | tr -d ' ') 行）"
