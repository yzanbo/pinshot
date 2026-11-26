#!/bin/bash
# 公開（make publish）の前に確かめる。そろっていなければ、何も作らずに止める。
#
# - 更新ファイルに署名する鍵があり、アプリに入れる公開鍵（project.yml の SUPublicEDKey）と合っている
#   （合わない鍵で署名すると、入れてもらったアプリが更新を受け付けなくなる）
# - main にいて、コミットしていない変更がなく、GitHub の main と同じ
#   （Release のタグは GitHub の main に付き、あとの appcast.xml のプッシュで手元の main も送るため）
# - この版（タグ v<版>）を、まだ GitHub に公開していない
#   （版を上げ忘れたまま流すと、DMG と zip を作り、appcast.xml を作り直したところで、Release を作れずに止まるため）
# 配る版に署名する証明書は、signing-check.sh で別に確かめる。
#
# 使い方: publish-check.sh <project.yml の公開鍵> <出す版（例: 0.5.0-beta.1）>
#
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-dev-cert.sh と同じ理由）。
set -euo pipefail

EXPECTED_KEY="${1:-}"
RELEASE_NAME="${2:-}"
BIN="Vendor/Sparkle/bin"

if [ -z "${EXPECTED_KEY}" ]; then
  echo "更新ファイルの署名の鍵が、まだありません。先に make update-key を流してください。" >&2
  exit 1
fi

KEYCHAIN_KEY="$("${BIN}/generate_keys" -p 2>/dev/null || true)"
if [ "${KEYCHAIN_KEY}" != "${EXPECTED_KEY}" ]; then
  echo "キーチェーンの鍵が、project.yml の SUPublicEDKey と合いません。" >&2
  echo "別の Mac で作った鍵なら、控えを ${BIN}/generate_keys -f <控えのファイル> で取り込んでください。" >&2
  exit 1
fi

if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
  echo "main ではないブランチにいます。PR をマージしたあと、git checkout main && git pull をしてから、公開してください。" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "コミットしていない変更があります。コミットしてプッシュしてから、公開してください。" >&2
  exit 1
fi

git fetch -q origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  echo "手元の main が、GitHub の main と違います。プッシュ（か pull）してから、公開してください。" >&2
  exit 1
fi

if [ -n "$(git ls-remote --tags origin "refs/tags/v${RELEASE_NAME}")" ]; then
  echo "v${RELEASE_NAME} は、もう公開しています。版とビルド番号を上げた変更（PR）を main に入れてから、公開してください。" >&2
  exit 1
fi
