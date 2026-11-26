DERIVED_DATA := build
APP := $(DERIVED_DATA)/Build/Products/Debug/Pinshot.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Pinshot.app
# アプリの識別子（project.yml の PRODUCT_BUNDLE_IDENTIFIER）
BUNDLE_ID := dev.portfolio.pinshot
# make install で入れる場所
INSTALL_DIR ?= /Applications
# アプリの版（project.yml の CFBundleShortVersionString）
VERSION := $(shell sed -n 's/.*CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)
# β 版として出すときは BETA=1 のように番号を渡す（タグは v0.1.0-beta.1、GitHub ではプレリリースにする）
BETA ?=
RELEASE_NAME := $(VERSION)$(if $(BETA),-beta.$(BETA))
DIST_BASE := dist/Pinshot-$(RELEASE_NAME)
DIST_ZIP := $(DIST_BASE).zip
DIST_DMG := $(DIST_BASE).dmg

# 「Pinshot Dev」の証明書があればそれで署名する（なければアドホック署名）。
# 毎回同じ証明書で署名すると、画面収録の許可がビルドし直しても外れない。
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"Pinshot Dev"' && echo "Pinshot Dev" || echo "-")

# 配る版（make dist）に署名する証明書。作者の「Pinshot Dev」を、名前ではなく SHA-1 で選ぶ
# （どの版も同じ証明書で署名して、更新しても許可が外れないようにする。理由は docs/ARCHITECTURE.md の「署名」）
RELEASE_SIGN_IDENTITY := 7BE0770552795F55842DBA3F671DB54505C9992A

# 更新の仕組み（Sparkle）。公式の配布物を取り寄せて Vendor/Sparkle に置く（リポジトリには入れない）。
# 版を上げるときは、SPARKLE_VERSION と SPARKLE_SHA256（配布物 Sparkle-版.tar.xz の SHA-256）を一緒に変える
SPARKLE_VERSION := 2.10.1
SPARKLE_SHA256 := 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_DIR := Vendor/Sparkle
# 取り寄せた版の印（版を上げると名前が変わり、取り寄せ直す）
SPARKLE_STAMP := $(SPARKLE_DIR)/.version-$(SPARKLE_VERSION)
# 更新ファイルの署名を確かめる公開鍵（project.yml の SUPublicEDKey。make update-key が書き込む）
UPDATE_PUBLIC_KEY := $(shell sed -n 's/^ *SUPublicEDKey: *"\(.*\)"/\1/p' project.yml)
# 配る更新ファイル（zip）を置く場所。版の一覧（appcast.xml）の中のダウンロード元になる
RELEASE_DOWNLOAD_URL := https://github.com/yzanbo/pinshot/releases/download/v$(RELEASE_NAME)/
# 更新の試験用アプリ（make update-test）に署名する証明書。配る版とまったく同じにする（許可が引き継がれるかを確かめるため）。
# アドホック署名どうしの更新と比べるときは make update-test UPDATE_TEST_SIGN_IDENTITY=-
UPDATE_TEST_SIGN_IDENTITY ?= $(RELEASE_SIGN_IDENTITY)
# 更新の試験で、新しい版を配る手元のサーバーのポート（Pinshelf の試験の 8765 とぶつからないよう、8766 にする）。
# ほかで使っているときは make update-test UPDATE_TEST_PORT=8800 のように替える
UPDATE_TEST_PORT ?= 8766

.PHONY: generate build release install uninstall dist publish publish-check test run stop clean cert icon readme-images \
	sparkle update-key update-test update-test-log

# アイコンを描くスクリプトをビルドする場所
ICON_TOOL_DIR := $(DERIVED_DATA)/icon-tool

# project.yml から Pinshot.xcodeproj を作る（Sparkle がまだなければ、先に取り寄せる）
generate: $(SPARKLE_STAMP)
	xcodegen generate

# Sparkle（更新の仕組み）を取り寄せる。ビルドの前に自動で行うので、ふだんは自分で呼ばなくてよい。
# 取り寄せたファイルは、決めてある SHA-256 と合うことを確かめてから使う（合わなければ止まる）
sparkle: $(SPARKLE_STAMP)

$(SPARKLE_STAMP):
	rm -rf "$(SPARKLE_DIR)"
	mkdir -p "$(SPARKLE_DIR)"
	curl -fsSL -o "$(SPARKLE_DIR)/Sparkle.tar.xz" \
		"https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz"
	echo "$(SPARKLE_SHA256)  $(SPARKLE_DIR)/Sparkle.tar.xz" | shasum -a 256 -c -
	@# 使うものだけ取り出す: アプリに入れるフレームワーク・署名と版の一覧の道具・ライセンス
	tar -xJf "$(SPARKLE_DIR)/Sparkle.tar.xz" -C "$(SPARKLE_DIR)" ./Sparkle.framework ./bin ./LICENSE
	rm "$(SPARKLE_DIR)/Sparkle.tar.xz"
	@# Sparkle のライセンスは、配るものに全文を含める決まりなので、アプリに同梱するファイルへ写す（リポジトリに入れる）
	mkdir -p Pinshot/Licenses
	cp "$(SPARKLE_DIR)/LICENSE" Pinshot/Licenses/Sparkle.txt
	touch "$@"

build: generate
	@echo "署名: $(SIGN_IDENTITY)"
	xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" build

# 配布用（Release）にビルドする。Intel と Apple Silicon の両方で動く形にする
release: generate
	@echo "署名: $(SIGN_IDENTITY)"
	xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -configuration Release \
		-derivedDataPath $(DERIVED_DATA) CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" ONLY_ACTIVE_ARCH=NO build

# Release 版をビルドして、アプリケーションフォルダに入れる（前の版は置き換える）
install: release stop
	mkdir -p "$(INSTALL_DIR)/Pinshot.app"
	rsync -a --delete "$(RELEASE_APP)/" "$(INSTALL_DIR)/Pinshot.app/"
	@echo ""
	@echo "$(INSTALL_DIR)/Pinshot.app に入れました。アプリケーションフォルダから Pinshot を開いてください。"

# アプリケーションフォルダから Pinshot を消す（設定と許可は残る）
uninstall: stop
	rm -rf "$(INSTALL_DIR)/Pinshot.app"

# GitHub の Releases に置く DMG と zip を作る（dist/Pinshot-版.dmg・.zip・.sha256）。
# DMG は、開くと Pinshot.app とアプリケーションフォルダが並び、ドラッグで入れられる形にする。
# 配る版は、いつも決まった証明書（RELEASE_SIGN_IDENTITY）で署名する。その証明書がこの Mac になければ、
# 控えの取り込み方を出して、ビルドの前に止める。ビルドのあとに、その証明書で署名されたかも確かめる
dist:
	./scripts/signing-check.sh keychain "$(RELEASE_SIGN_IDENTITY)"
	$(MAKE) release SIGN_IDENTITY="$(RELEASE_SIGN_IDENTITY)"
	./scripts/signing-check.sh app "$(RELEASE_APP)" "$(RELEASE_SIGN_IDENTITY)"
	mkdir -p dist
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" "$(DIST_ZIP)"
	rm -rf dist/dmg-root
	mkdir -p dist/dmg-root
	ditto "$(RELEASE_APP)" dist/dmg-root/Pinshot.app
	ln -s /Applications dist/dmg-root/Applications
	@# macOS 26 以降は diskutil image で作る（hdiutil create は「使わなくなる」と警告が出るため）。ない版では hdiutil で作る
	rm -f "$(DIST_DMG)"
	if diskutil image create from -h >/dev/null 2>&1; then \
		diskutil image create from --format UDZO --volumeName "Pinshot" dist/dmg-root "$(DIST_DMG)"; \
	else \
		hdiutil create -volname "Pinshot" -srcfolder dist/dmg-root -ov -format UDZO "$(DIST_DMG)"; \
	fi
	rm -rf dist/dmg-root
	cd dist && shasum -a 256 "Pinshot-$(RELEASE_NAME).dmg" "Pinshot-$(RELEASE_NAME).zip" > "Pinshot-$(RELEASE_NAME).sha256"
	@echo ""
	@echo "$(DIST_DMG) と $(DIST_ZIP) を作りました（版: $(RELEASE_NAME)）"

# DMG と zip を作り、GitHub に Release（タグ v版）を作ってアップロードする（GitHub CLI を使う）。
# 説明は「この版の変更」（scripts/release-changes.md。出すたびに書き直す）と「ダウンロードと開き方」をつなげる。
# β 版のときは、説明の先頭に β 版の注意を付け、プレリリースにする。
#
# 入れてもらったアプリに更新を届けるため、zip に EdDSA の鍵で署名して、版の一覧（appcast.xml）を作り直す。
# Release を作ったあと、appcast.xml だけをコミットしてプッシュする（アプリは、main の appcast.xml を見て新しい版を知る）
publish: publish-check dist
	( $(if $(BETA),cat scripts/release-notes-beta.md; echo;) cat scripts/release-changes.md; echo; cat scripts/release-notes.md ) > dist/release-notes.md
	./scripts/make-appcast.sh "$(DIST_ZIP)" scripts/release-changes.md "$(RELEASE_DOWNLOAD_URL)" appcast.xml
	gh release create "v$(RELEASE_NAME)" "$(DIST_DMG)" "$(DIST_ZIP)" "$(DIST_BASE).sha256" \
		--target main --title "Pinshot $(RELEASE_NAME)$(if $(BETA), (β 版))" $(if $(BETA),--prerelease) \
		--notes-file dist/release-notes.md
	git add appcast.xml
	git commit -q -m "chore: 版の一覧（appcast）を $(RELEASE_NAME) にする" -- appcast.xml
	git push origin main
	@echo ""
	@echo "$(RELEASE_NAME) を公開しました。入れてもらったアプリには、appcast.xml を通して新しい版が届きます。"

# 公開の前に確かめる（そろっていなければ、何も作らずに止める。署名の証明書は、dist がビルドの前に確かめる）
# - 更新ファイルに署名する鍵があり、アプリに入れる公開鍵（project.yml）と合っている（合わない鍵で署名すると、更新が届かなくなる）
# - コミットしていない変更がなく、GitHub の main と同じ（Release のタグは GitHub の main に付き、appcast.xml のプッシュで手元の main も送るため）
# - この版（タグ v版）を、まだ公開していない（版を上げ忘れたまま流すと、appcast.xml だけ作り直して止まるため）
publish-check: $(SPARKLE_STAMP)
	./scripts/publish-check.sh "$(UPDATE_PUBLIC_KEY)" "$(RELEASE_NAME)"

# 更新ファイルの署名に使う鍵（EdDSA）を用意して、公開鍵を project.yml に書き込む（最初の 1 回だけ。鍵は Pin シリーズで共通）。
# 秘密鍵は、この Mac のログインキーチェーンに入る（途中で、キーチェーンへのアクセスを聞かれたら許可する）
update-key: $(SPARKLE_STAMP)
	./scripts/update-key.sh

# 更新を、手元で通しで試す（docs/TESTING.md の「更新を通しで試す」）。
# ふだんの Pinshot とは別の ID・別のデータフォルダの試験用アプリを、配る版と同じ証明書で 2 つの版作り、
# 新しい版を手元のサーバーから配る（止めるときは control + C）
update-test: generate
	SIGN_IDENTITY="$(UPDATE_TEST_SIGN_IDENTITY)" UPDATE_TEST_PORT="$(UPDATE_TEST_PORT)" ./scripts/update-test.sh

# 更新の試験のあいだの macOS の記録を、build/update-test/system.log に書き出す
# （許可が引き継がれたかの裏取りと、うまくいかないときの手がかりに使う）。
# いつからの記録かは SINCE="2026-11-26 19:50:00" のように渡す（なければ、直近 30 分）
update-test-log:
	./scripts/update-test-log.sh

# テストを動かす（アプリは起動しない）。
# xcodebuild test は端末によっては動かないので、ビルドしてから xctest で直接動かす
test: generate
	xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" build-for-testing
	xcrun xctest $(DERIVED_DATA)/Build/Products/Debug/PinshotTests.xctest

# 動いている Pinshot を終了してから、ビルドして起動する
run: build stop
	@# 念のため、開けなかったときは少し待って開き直す（最後の 1 回だけ、エラーを出す）
	@for i in 1 2 3 4; do open "$(APP)" 2>/dev/null && exit 0; sleep 0.5; done; open "$(APP)"

# 浮かせている画像を保存してから終わるので、終わり切るまで（最大 5 秒）待つ。
# プロセスが消えても、macOS（LaunchServices）が終了を知るのは少し遅れる。知る前に open すると、
# 終わった Pinshot に起動の知らせを送ろうとして -600 で失敗するので、知るまで待つ（最大 5 秒）
stop:
	-@killall Pinshot 2>/dev/null; for i in $$(seq 1 50); do pgrep -x Pinshot >/dev/null || break; sleep 0.1; done
	@for i in $$(seq 1 50); do [ -z "$$(lsappinfo find bundleid=$(BUNDLE_ID) 2>/dev/null)" ] && break; sleep 0.1; done

clean:
	xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -derivedDataPath $(DERIVED_DATA) clean
	rm -rf $(DERIVED_DATA)/update-test

# README の絵（docs/images のいちばん上の静止画 hero.png と、使い方の GIF）を作り直す（Pinshot の見た目・動きを変えたとき）。
# アプリのコード（入口の AppDelegate と、Sparkle を読み込む SparkleUpdater を除く）と scripts/readme-images/main.swift を一緒にビルドし、
# Pinshot の部品を実際に出して描き写す。
# 作っている間、画面に Pinshot の部品が少しのあいだ出る（マウス・キーボードの操作や、画面の収録はしない）
README_TOOL_DIR := $(DERIVED_DATA)/readme-images
readme-images:
	mkdir -p "$(README_TOOL_DIR)"
	find Pinshot -name '*.swift' ! -name AppDelegate.swift ! -name SparkleUpdater.swift > "$(README_TOOL_DIR)/sources.txt"
	echo scripts/readme-images/main.swift >> "$(README_TOOL_DIR)/sources.txt"
	xcrun swiftc -swift-version 5 -target $(shell uname -m)-apple-macos14.0 -module-name ReadmeImages \
		-module-cache-path "$(README_TOOL_DIR)/module-cache" @"$(README_TOOL_DIR)/sources.txt" -o "$(README_TOOL_DIR)/ReadmeImages"
	"$(README_TOOL_DIR)/ReadmeImages" docs/images

# アプリのアイコンを描き直す（scripts/make-app-icon.swift を変えたとき）
icon:
	mkdir -p $(ICON_TOOL_DIR)
	swiftc -O -module-cache-path $(ICON_TOOL_DIR)/cache scripts/make-app-icon.swift -o $(ICON_TOOL_DIR)/make-app-icon
	$(ICON_TOOL_DIR)/make-app-icon

# 開発用の署名の証明書を作る（一度だけ）
cert:
	./scripts/create-dev-cert.sh
