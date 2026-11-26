#!/bin/bash
# 配る版に署名する証明書を確かめる（make dist・make update-test が呼ぶ）。
#
# 配る版は、作者の「Pinshot Dev」を名前ではなく SHA-1 で選んで署名する（Makefile の RELEASE_SIGN_IDENTITY。
# 理由は docs/ARCHITECTURE.md の「署名」）。SHA-1 で選ぶので、作り直した証明書では、そもそも署名できない。
# ここでは、その証明書がないときに控えの取り込み方を出し、署名のあとに、その証明書で署名されたかを確かめる。
#
# 使い方:
#   signing-check.sh keychain <証明書の SHA-1>        この Mac に、その証明書があるか（ビルドの前）
#   signing-check.sh app <アプリ> <証明書の SHA-1>    ビルドしたアプリが、その証明書で署名されているか（ビルドのあと）
#
# 変数のすぐ後ろに全角の文字を続けるときは、${NAME} と波かっこで囲む（create-dev-cert.sh と同じ理由）。
set -euo pipefail

USAGE="使い方: signing-check.sh keychain <証明書の SHA-1> | app <アプリ> <証明書の SHA-1>"

case "${1:-}" in
  keychain)
    [ "$#" -eq 2 ] || { echo "${USAGE}" >&2; exit 1; }
    if ! security find-identity -v -p codesigning | grep -qi "$2"; then
      echo "配る版に署名する証明書（SHA-1: $2）が、この Mac にありません（有効期限が切れたときも、ここで止まります）。" >&2
      echo "「Pinshot Dev」の控え（.p12）を取り込んでください（docs/ARCHITECTURE.md の「署名」）。" >&2
      echo "make cert で作り直すと別の証明書になり、それで配ると、更新を入れた人の許可が外れます。" >&2
      exit 1
    fi
    ;;
  app)
    [ "$#" -eq 3 ] || { echo "${USAGE}" >&2; exit 1; }
    APP="$2"
    EXPECTED="$(echo "$3" | tr '[:upper:]' '[:lower:]')"
    REQUIREMENT="$(codesign -d -r- "${APP}" 2>&1)"
    if ! echo "${REQUIREMENT}" | grep -qF "certificate leaf = H\"${EXPECTED}\""; then
      echo "${APP} が、配る版の証明書（SHA-1: $3）で署名されていません:" >&2
      echo "${REQUIREMENT}" >&2
      exit 1
    fi
    codesign --verify --deep --strict "${APP}"
    echo "署名を確かめました: ${APP}（証明書の SHA-1: $3）"
    ;;
  *)
    echo "${USAGE}" >&2
    exit 1
    ;;
esac
