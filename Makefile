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

# 更新の仕組み（Sparkle）。公式の配布物を取り寄せて Vendor/Sparkle に置く（リポジトリには入れない）。
# 版を上げるときは、SPARKLE_VERSION と SPARKLE_SHA256（配布物 Sparkle-版.tar.xz の SHA-256）を一緒に変える
SPARKLE_VERSION := 2.10.1
SPARKLE_SHA256 := 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_DIR := Vendor/Sparkle
# 取り寄せた版の印（版を上げると名前が変わり、取り寄せ直す）
SPARKLE_STAMP := $(SPARKLE_DIR)/.version-$(SPARKLE_VERSION)

.PHONY: generate build release install uninstall dist publish test run stop clean cert icon readme-images \
	sparkle

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
# 自己署名の証明書はほかの Mac では意味がないので、配る版はいつもアドホック署名にする
dist:
	$(MAKE) release SIGN_IDENTITY=-
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
# β 版のときは、説明の先頭に β 版の注意を付け、プレリリースにする
publish: dist
	( $(if $(BETA),cat scripts/release-notes-beta.md; echo;) cat scripts/release-changes.md; echo; cat scripts/release-notes.md ) > dist/release-notes.md
	gh release create "v$(RELEASE_NAME)" "$(DIST_DMG)" "$(DIST_ZIP)" "$(DIST_BASE).sha256" \
		--target main --title "Pinshot $(RELEASE_NAME)$(if $(BETA), (β 版))" $(if $(BETA),--prerelease) \
		--notes-file dist/release-notes.md

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
