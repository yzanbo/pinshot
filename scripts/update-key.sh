#!/bin/bash
# 更新ファイルの署名に使う鍵（EdDSA）を用意して、公開鍵を project.yml に書き込む（make update-key）。
#
# 秘密鍵は、Sparkle の道具（generate_keys）が、この Mac のログインキーチェーンに作って入れる。
# もう鍵があれば作り直さず、その鍵の公開鍵を書き込む（鍵は 1 つで、Pin シリーズのどのアプリにも使える。
# Pinshelf で作った鍵があれば、それがそのまま入る）。
# 途中でキーチェーンへのアクセスを聞かれたら、許可する。
#
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-dev-cert.sh と同じ理由）。
set -euo pipefail

BIN="Vendor/Sparkle/bin"

# 鍵がなければ作る（あれば、そのまま使う）
"${BIN}/generate_keys" >/dev/null
PUBLIC_KEY="$("${BIN}/generate_keys" -p)"
if [ -z "${PUBLIC_KEY}" ]; then
  echo "公開鍵を読めませんでした。" >&2
  exit 1
fi

# project.yml の SUPublicEDKey を、この公開鍵にする（公開鍵は秘密ではないので、リポジトリに入れてよい）
/usr/bin/sed -i '' -E "s|^( *SUPublicEDKey: ).*|\\1\"${PUBLIC_KEY}\"|" project.yml
if ! grep -q "SUPublicEDKey: \"${PUBLIC_KEY}\"" project.yml; then
  echo "project.yml の SUPublicEDKey を書き換えられませんでした。" >&2
  exit 1
fi

echo
echo "公開鍵を project.yml に書き込みました: ${PUBLIC_KEY}"
echo "（git diff project.yml で変わっていなければ、入っていた鍵と同じです）"
echo
echo "秘密鍵は、この Mac のログインキーチェーンにあります（名前: Private key for signing Sparkle updates）。"
echo "失くすと、入れてもらったアプリに更新を届けられなくなるので、まだなら控えを取ってください:"
echo "  ${BIN}/generate_keys -x sparkle-private-key.txt"
echo "書き出したファイルの中身をパスワード管理アプリなどに保管したら、ファイルは消します（Git には入れません）。"
