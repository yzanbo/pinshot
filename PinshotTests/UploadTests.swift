import XCTest

/// 録画を GIF にして上げるときの大きさと、進み具合の知らせの文
final class GIFUploadRulesTests: XCTestCase {
    func testGIFSizeLimit() {
        XCTAssertTrue(UploadRules.fitsGIFUpload(bytes: UploadRules.gifMaxBytes))
        XCTAssertFalse(UploadRules.fitsGIFUpload(bytes: UploadRules.gifMaxBytes + 1))
    }

    func testStatusText() {
        XCTAssertEqual(UploadStatus.working("Gyazo に上げています…", progress: 0.454).displayText, "Gyazo に上げています… 45%")
        XCTAssertEqual(UploadStatus.working("GIF を作っています…", progress: nil).displayText, "GIF を作っています…")
        XCTAssertEqual(UploadStatus.finished("リンクをコピーしました").displayText, "リンクをコピーしました")
        XCTAssertTrue(UploadStatus.working("", progress: nil).isWorking)
        XCTAssertFalse(UploadStatus.finished("").isWorking)
    }
}

/// クリップボードに入れる文・ファイル名・multipart の本文
final class UploadRulesTests: XCTestCase {
    private let page = URL(string: "https://gyazo.com/abc")!
    private let direct = URL(string: "https://i.gyazo.com/abc.png")!

    func testClipboardTextForEachFormat() {
        let link = SharedLink(pageURL: page, directURL: direct)
        XCTAssertEqual(UploadRules.clipboardText(for: link, format: .page), "https://gyazo.com/abc")
        XCTAssertEqual(UploadRules.clipboardText(for: link, format: .direct), "https://i.gyazo.com/abc.png")
        XCTAssertEqual(UploadRules.clipboardText(for: link, format: .markdown), "![](https://i.gyazo.com/abc.png)")
    }

    func testClipboardTextFallsBackToPageWithoutDirectURL() {
        let link = SharedLink(pageURL: page, directURL: nil)
        XCTAssertEqual(UploadRules.clipboardText(for: link, format: .direct), "https://gyazo.com/abc")
        XCTAssertEqual(UploadRules.clipboardText(for: link, format: .markdown), "![](https://gyazo.com/abc)")
    }

    func testCapabilitiesAccepts() {
        let capabilities = UploadCapabilities(uploadsMovies: false, canDelete: true, maxFileBytes: 100)
        XCTAssertTrue(capabilities.accepts(.image, bytes: 100))
        XCTAssertFalse(capabilities.accepts(.image, bytes: 101))
        XCTAssertFalse(capabilities.accepts(.movie, bytes: 1))
    }

    func testLooksLikeAccessToken() {
        XCTAssertTrue(UploadRules.looksLikeAccessToken("8980c52421e452ac3355ca3e5cfe7a0c8980c52421e452ac"))
        XCTAssertTrue(UploadRules.looksLikeAccessToken("  abcDEF123-_.~abcDEF123\n"))
        XCTAssertFalse(UploadRules.looksLikeAccessToken("short"))
        XCTAssertFalse(UploadRules.looksLikeAccessToken("https://gyazo.com/oauth/applications"))
        XCTAssertFalse(UploadRules.looksLikeAccessToken("これはトークンではありません。これはトークンではありません。"))
        XCTAssertFalse(UploadRules.looksLikeAccessToken("abc def ghi jkl mno pqr stu"))
    }

    func testFileNameHasNoSpaces() {
        let date = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18 ごろ
        let name = UploadRules.fileName(kind: .image, date: date, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(name, "Pinshot-2026-11-18-200640.png")
        XCTAssertFalse(name.contains(" "))
        XCTAssertTrue(UploadRules.fileName(kind: .movie, date: date).hasSuffix(".mp4"))
    }

    func testMultipartBody() {
        var form = MultipartForm(boundary: "B")
        form.addField(name: "access_policy", value: "anyone")
        form.addFile(name: "imagedata", fileName: "a.png", mimeType: "image/png", data: Data("PNG".utf8))
        let body = String(decoding: form.finalized(), as: UTF8.self)
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=B")
        XCTAssertEqual(body, """
        --B\r
        Content-Disposition: form-data; name="access_policy"\r
        \r
        anyone\r
        --B\r
        Content-Disposition: form-data; name="imagedata"; filename="a.png"\r
        Content-Type: image/png\r
        \r
        PNG\r
        --B--\r

        """)
    }
}

/// PKCE とログインの URL・本文・返事
final class OAuthTests: XCTestCase {
    private let configuration = OAuthConfiguration(
        authorizeURL: URL(string: "https://auth.example.com/oauth2/authorize")!,
        tokenURL: URL(string: "https://api.example.com/oauth2/token")!,
        clientID: "app key",
        scopes: ["files.content.write", "sharing.write"],
        extraAuthorizeParameters: ["token_access_type": "offline"],
        redirect: .loopback(ports: [53682, 53683, 53684], path: "/oauth/callback")
    )

    func testPKCEChallengeMatchesRFC7636Example() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(pkce.method, "S256")
    }

    func testGeneratedVerifierIsURLSafeAndUnique() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertGreaterThanOrEqual(a.verifier.count, 43)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        XCTAssertTrue(a.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    func testAuthorizationURL() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = configuration.authorizationURL(
            redirectURI: OAuthRedirect.loopbackURI(port: 53683, path: "/oauth/callback"),
            state: "s1",
            pkce: pkce
        )
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(url.host, "auth.example.com")
        XCTAssertEqual(value("client_id"), "app key")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("code_challenge"), pkce.challenge)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("state"), "s1")
        XCTAssertEqual(value("redirect_uri"), "http://localhost:53683/oauth/callback")
        XCTAssertEqual(value("scope"), "files.content.write sharing.write")
        XCTAssertEqual(value("token_access_type"), "offline")
    }

    func testAuthorizationURLWithoutRedirect() {
        let url = configuration.authorizationURL(redirectURI: nil, state: "s", pkce: .generate())
        let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []
        XCTAssertFalse(names.contains("redirect_uri"))
    }

    func testTokenRequestBodies() {
        let pkce = PKCE(verifier: "v~1")
        let body = String(decoding: configuration.tokenRequestBody(code: "c/d", pkce: pkce, redirectURI: "http://localhost:53682/oauth/callback"), as: UTF8.self)
        XCTAssertEqual(body, "grant_type=authorization_code&code=c%2Fd&code_verifier=v~1&client_id=app%20key&redirect_uri=http%3A%2F%2Flocalhost%3A53682%2Foauth%2Fcallback")
        let refresh = String(decoding: configuration.refreshRequestBody(refreshToken: "r+1"), as: UTF8.self)
        XCTAssertEqual(refresh, "grant_type=refresh_token&refresh_token=r%2B1&client_id=app%20key")
    }

    func testTokenResponse() throws {
        let json = Data(#"{"access_token":"a1","token_type":"bearer","expires_in":14400,"refresh_token":"r1"}"#.utf8)
        let now = Date(timeIntervalSince1970: 1000)
        let token = try JSONDecoder().decode(OAuthTokenResponse.self, from: json).token(receivedAt: now)
        XCTAssertEqual(token, OAuthToken(accessToken: "a1", refreshToken: "r1", expiresAt: Date(timeIntervalSince1970: 15400)))

        // 取り直したときの返事に refresh_token がなければ、前のものを使い続ける
        let refreshed = Data(#"{"access_token":"a2","expires_in":14400}"#.utf8)
        let next = try JSONDecoder().decode(OAuthTokenResponse.self, from: refreshed).token(receivedAt: now, keepingRefreshToken: "r1")
        XCTAssertEqual(next.refreshToken, "r1")
    }

    func testNeedsRefresh() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(OAuthToken(accessToken: "a", refreshToken: nil, expiresAt: nil).needsRefresh(now: now))
        XCTAssertFalse(OAuthToken(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(600)).needsRefresh(now: now))
        XCTAssertTrue(OAuthToken(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(60)).needsRefresh(now: now))
    }

    func testCallbackFromRequestLine() {
        XCTAssertEqual(
            OAuthCallback(requestLine: "GET /oauth/callback?code=abc&state=s1 HTTP/1.1", expectedPath: "/oauth/callback"),
            .code("abc", state: "s1")
        )
        XCTAssertEqual(
            OAuthCallback(requestLine: "GET /oauth/callback?error=access_denied&error_description=No HTTP/1.1", expectedPath: "/oauth/callback"),
            .denied("No")
        )
        // ブラウザが勝手に聞くもの・違う場所は読まない
        XCTAssertNil(OAuthCallback(requestLine: "GET /favicon.ico HTTP/1.1", expectedPath: "/oauth/callback"))
        XCTAssertNil(OAuthCallback(requestLine: "POST /oauth/callback?code=abc HTTP/1.1", expectedPath: "/oauth/callback"))
        XCTAssertNil(OAuthCallback(requestLine: "GET /oauth/callback HTTP/1.1", expectedPath: "/oauth/callback"))
    }
}

/// 上げたものの履歴
final class UploadHistoryTests: XCTestCase {
    private func entry(_ id: UUID = UUID(), date: Date = Date(timeIntervalSince1970: 1_795_000_000)) -> UploadHistoryEntry {
        UploadHistoryEntry(
            id: id,
            date: date,
            remote: RemoteFile(destination: .gyazo, id: "abc", info: ["pageURL": "https://gyazo.com/abc"]),
            link: SharedLink(pageURL: URL(string: "https://gyazo.com/abc")!, directURL: URL(string: "https://i.gyazo.com/abc.png")),
            kind: .image,
            fileName: "Pinshot-2026-11-18-200640.png"
        )
    }

    func testEntryRoundTripsThroughJSON() throws {
        let original = entry()
        let decoded = try JSONDecoder().decode(UploadHistoryEntry.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.destination, .gyazo)
        XCTAssertEqual(decoded.thumbnailFileName, "\(original.id.uuidString).thumb.png")
    }

    func testAddingPutsNewestFirstAndReplacesSameID() {
        let id = UUID()
        let old = entry(id)
        let other = entry()
        var updated = old
        updated.fileName = "new.png"
        let list = UploadHistoryRules.adding(updated, to: [other, old])
        XCTAssertEqual(list.map(\.id), [id, other.id])
        XCTAssertEqual(list.first?.fileName, "new.png")
    }

    func testShortLink() {
        XCTAssertEqual(UploadHistoryRules.shortLink(URL(string: "https://gyazo.com/8980c524")!), "gyazo.com/8980c524")
        XCTAssertEqual(UploadHistoryRules.shortLink(URL(string: "https://example.com/")!), "example.com")
    }
}
