#!/bin/bash
# コード署名の証明書を、ログインキーチェーンに作る（make cert）。名前は Makefile の CERT_NAME（作者は「yzanbo Code Signing」）。
#
# 使い方: create-signing-cert.sh <証明書の名前>
#
# 作者のアプリ（Pin シリーズ・Kickoff など）すべてで、この 1 つの証明書を使う（Developer ID と同じく、開発者ごとに 1 つ）。
# macOS は「アプリの ID ＋ 証明書」で同じアプリかを見分けるので、毎回この証明書で署名すれば、ビルドし直しても・版を上げても、
# 画面収録などの許可が外れない。アプリの ID が違うので、同じ証明書でも、アプリどうしの許可は混ざらない。
# Pinshot は、配る版（make dist）にもこの証明書で署名する。
#
# 作るのは最初の 1 回だけ（どのリポジトリの make cert でも、同じ名前の証明書があれば作らず、その SHA-1 を出す）。
# 作り直した証明書は、名前が同じでも別物なので、別の Mac では作らずに控え（.p12）を取り込む。
# 決まりの全体は、共通のノート「署名の証明書の決まり」と docs/ARCHITECTURE.md の「署名」。
# 途中で、キーチェーンの変更を許可するためのパスワードを聞かれる。
set -euo pipefail

NAME="${1:?使い方: create-signing-cert.sh <証明書の名前>（make cert から流す）}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# 証明書の SHA-1（配る版の署名では、名前ではなくこれで選ぶ。Makefile の RELEASE_SIGN_IDENTITY）
sha1_of_identity() {
  security find-identity -v -p codesigning | grep -F "\"${NAME}\"" | awk '{print $2}' | sort -u
}

# 全角の文字のすぐ前の変数は、${NAME} と波かっこで囲む（macOS の bash 3.2 は、言語の設定が UTF-8 のとき、
# 続く全角の文字のバイトまで変数名として読み、「NAME�: unbound variable」で止まるため）
EXISTING="$(sha1_of_identity || true)"
if [ -n "${EXISTING}" ]; then
  echo "「${NAME}」の証明書はすでにあります（SHA-1: ${EXISTING}）。"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 有効期限は、日本時間の 9999-12-31 23:59:59（世界標準時の 9999-12-31 14:59:59）。
# 9999-12-31 は、証明書の決まり（RFC 5280）で「期限を定めない」ことを表す日付で、実質、期限なし
# （切れると新しい版に署名できなくなり、作り直した版では、使う人全員が許可を 1 回取り直すため）。
# 世界標準時の 23:59:59 にすると、日本時間では 10000-01-01 になり、キーチェーンアクセスでの見え方がおかしくなるおそれがあるので、
# 日本時間で 9999-12-31 に収める
NOT_AFTER="99991231145959Z"

cat > "$WORK/req.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
[ dn ]
CN = $NAME
EOF

# 終わりの日時をじかに渡すため、openssl req -x509（日数でしか渡せず、終わりの時刻が作った時刻になる）ではなく、
# openssl ca で自分の鍵で自分に署名する（-selfsign）。ca に要る台帳（index.txt・serial）は一時フォルダに置く
cat > "$WORK/ca.cnf" <<EOF
[ ca ]
default_ca = selfsign
[ selfsign ]
database = $WORK/index.txt
new_certs_dir = $WORK
serial = $WORK/serial
default_md = sha256
policy = policy_any
unique_subject = no
email_in_dn = no
copy_extensions = none
[ policy_any ]
commonName = supplied
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF
: > "$WORK/index.txt"
# 証明書の番号は、作るたびに違う値にする（キーチェーンは「発行者と番号」で証明書を見分けるので、万一作り直したときにぶつからないように）
/usr/bin/openssl rand -hex 16 > "$WORK/serial"

# macOS 標準の openssl（LibreSSL）を使う（キーチェーンが読める形式で書き出すため）
/usr/bin/openssl req -new -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/req.csr" -config "$WORK/req.cnf" 2>/dev/null
/usr/bin/openssl ca -batch -selfsign -notext -config "$WORK/ca.cnf" -keyfile "$WORK/key.pem" \
  -in "$WORK/req.csr" -out "$WORK/cert.pem" -extensions ext -enddate "${NOT_AFTER}" 2>/dev/null
# キーチェーンへ取り込むための一時の .p12（取り込んだら、一時フォルダごと消える。控えは別に書き出す）
/usr/bin/openssl pkcs12 -export -name "$NAME" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/cert.p12" -passout pass:import

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P import -T /usr/bin/codesign
# コード署名に使う証明書として信頼する（ここでパスワードを聞かれる）
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
echo "「${NAME}」の証明書を作りました（SHA-1: $(sha1_of_identity)）。"
echo "make run・make install でビルドすると、この証明書で署名されます。"
echo "初めて署名するときに、codesign がキーチェーンの鍵を使ってよいかを聞かれます。ログインパスワードを入れて「常に許可」を押してください"
echo "（許可するまでは、署名が errSecInternalComponent で止まります）。"
echo "失くすと作り直せないので、キーチェーンアクセスで書き出して、パスワード付きの控え（.p12）を Mac の外に保管してください。"
