DERIVED_DATA := build
APP := $(DERIVED_DATA)/Build/Products/Debug/Pinshot.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Pinshot.app
# make install で入れる場所
INSTALL_DIR ?= /Applications
# アプリの版（project.yml の CFBundleShortVersionString）
VERSION := $(shell sed -n 's/.*CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)
DIST_ZIP := dist/Pinshot-$(VERSION).zip

# 「Pinshot Dev」の証明書があればそれで署名する（なければアドホック署名）。
# 毎回同じ証明書で署名すると、画面収録の許可がビルドし直しても外れない。
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"Pinshot Dev"' && echo "Pinshot Dev" || echo "-")

.PHONY: generate build release install uninstall dist publish test run stop clean cert icon

# アイコンを描くスクリプトをビルドする場所
ICON_TOOL_DIR := $(DERIVED_DATA)/icon-tool

# project.yml から Pinshot.xcodeproj を作る
generate:
	xcodegen generate

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

# GitHub の Releases に置く zip を作る（dist/Pinshot-版.zip）。
# 自己署名の証明書はほかの Mac では意味がないので、配る版はいつもアドホック署名にする
dist:
	$(MAKE) release SIGN_IDENTITY=-
	mkdir -p dist
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" "$(DIST_ZIP)"
	cd dist && shasum -a 256 "Pinshot-$(VERSION).zip" > "Pinshot-$(VERSION).zip.sha256"
	@echo ""
	@echo "$(DIST_ZIP) を作りました（版: $(VERSION)）"

# zip を作り、GitHub に Release（タグ v版）を作ってアップロードする（GitHub CLI を使う）
publish: dist
	gh release create "v$(VERSION)" "$(DIST_ZIP)" "$(DIST_ZIP).sha256" \
		--target main --title "Pinshot $(VERSION)" --notes-file scripts/release-notes.md

# テストを動かす（アプリは起動しない）。
# xcodebuild test は端末によっては動かないので、ビルドしてから xctest で直接動かす
test: generate
	xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" build-for-testing
	xcrun xctest $(DERIVED_DATA)/Build/Products/Debug/PinshotTests.xctest

# 動いている Pinshot を終了してから、ビルドして起動する
run: build stop
	open $(APP)

stop:
	-@killall Pinshot 2>/dev/null; sleep 0.5

clean:
	xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -derivedDataPath $(DERIVED_DATA) clean

# アプリのアイコンを描き直す（scripts/make-app-icon.swift を変えたとき）
icon:
	mkdir -p $(ICON_TOOL_DIR)
	swiftc -O -module-cache-path $(ICON_TOOL_DIR)/cache scripts/make-app-icon.swift -o $(ICON_TOOL_DIR)/make-app-icon
	$(ICON_TOOL_DIR)/make-app-icon

# 開発用の署名の証明書を作る（一度だけ）
cert:
	./scripts/create-dev-cert.sh
