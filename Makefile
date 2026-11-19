DERIVED_DATA := build
APP := $(DERIVED_DATA)/Build/Products/Debug/Pinshot.app

# 「Pinshot Dev」の証明書があればそれで署名する（なければアドホック署名）。
# 毎回同じ証明書で署名すると、画面収録の許可がビルドし直しても外れない。
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"Pinshot Dev"' && echo "Pinshot Dev" || echo "-")

.PHONY: generate build test run stop clean cert icon

# アイコンを描くスクリプトをビルドする場所
ICON_TOOL_DIR := $(DERIVED_DATA)/icon-tool

# project.yml から Pinshot.xcodeproj を作る
generate:
	xcodegen generate

build: generate
	@echo "署名: $(SIGN_IDENTITY)"
	xcodebuild -project Pinshot.xcodeproj -scheme Pinshot -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" build

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
