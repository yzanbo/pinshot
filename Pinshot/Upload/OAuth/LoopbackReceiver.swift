import Foundation
import Network

/// ログインの間だけ、Pinshot の中に開く受け口（http://localhost:番号/path）。
/// 保存先のログイン画面で「許可する」を押すと、ブラウザがここを開くので、URL に付いた引換券を受け取る。
/// 外から届かないよう、この Mac の中（127.0.0.1 と ::1）だけで待つ
final class LoopbackReceiver: @unchecked Sendable {
    let port: UInt16
    private let path: String
    private var listeners: [NWListener] = []
    private let queue = DispatchQueue(label: "Pinshot.LoopbackReceiver")
    /// 待っている人と、先に届いた知らせ（どちらも queue の上で触る）
    private var waiter: CheckedContinuation<OAuthCallback, Error>?
    private var received: Result<OAuthCallback, Error>?

    private init(port: UInt16, path: String) {
        self.port = port
        self.path = path
    }

    /// ports のうち、空いている最初の番号で開く（どれもほかのアプリに使われていれば nil）
    static func start(ports: [UInt16], path: String) async -> LoopbackReceiver? {
        for port in ports {
            let receiver = LoopbackReceiver(port: port, path: path)
            if await receiver.open() { return receiver }
        }
        return nil
    }

    /// 引換券（か、断られた知らせ）が届くまで待つ
    func waitForCallback() async throws -> OAuthCallback {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let received = self.received {
                    continuation.resume(with: received)
                } else {
                    self.waiter = continuation
                }
            }
        }
    }

    /// 受け口を閉じる（待っている人がいれば、やめたことにする）
    func stop() {
        queue.async {
            self.listeners.forEach { $0.cancel() }
            self.listeners = []
            self.finish(.failure(UploadError.cancelled))
        }
    }

    // MARK: - 開く

    /// IPv4（127.0.0.1）で開けたら使う。IPv6（::1）は、この番号をほかのアプリが使っているときだけ、開けないとみなす
    private func open() async -> Bool {
        guard let v4 = await listen(host: "127.0.0.1") else { return false }
        var opened = [v4]
        switch await listenResult(host: "::1") {
        case .success(let v6):
            opened.append(v6)
        case .failure(let error) where Self.isAddressInUse(error):
            v4.cancel()
            return false
        case .failure:
            // IPv6 を使えない Mac では、IPv4 だけで待つ
            break
        }
        queue.sync { listeners = opened }
        return true
    }

    private func listen(host: String) async -> NWListener? {
        try? await listenResult(host: host).get()
    }

    private func listenResult(host: String) async -> Result<NWListener, Error> {
        guard let port = NWEndpoint.Port(rawValue: port) else { return .failure(UploadError.loopbackUnavailable) }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: port)
        parameters.allowLocalEndpointReuse = false
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            return .failure(error)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return await withCheckedContinuation { continuation in
            // 知らせは queue の上で 1 つずつ届くので、最初の結果だけを返す
            let once = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard once.claim() else { return }
                    continuation.resume(returning: .success(listener))
                case .failed(let error), .waiting(let error):
                    guard once.claim() else { return }
                    listener.cancel()
                    continuation.resume(returning: .failure(error))
                case .cancelled:
                    guard once.claim() else { return }
                    continuation.resume(returning: .failure(UploadError.cancelled))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private static func isAddressInUse(_ error: Error) -> Bool {
        if case .posix(let code) = error as? NWError { return code == .EADDRINUSE }
        return false
    }

    // MARK: - 届いたとき

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(on: connection, buffer: Data())
    }

    /// HTTP の頭（空行まで）を読む
    private func receiveHead(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let text = String(decoding: buffer, as: UTF8.self)
            if text.contains("\r\n\r\n") || isComplete || error != nil || buffer.count > 16384 {
                self.respond(to: text, on: connection)
            } else {
                self.receiveHead(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        guard let callback = OAuthCallback(requestLine: requestLine, expectedPath: path) else {
            send(status: "404 Not Found", body: "", on: connection)
            return
        }
        let message: String
        switch callback {
        case .code: message = "ログインできました。Pinshot に戻ってください（このページは閉じてかまいません）。"
        case .denied: message = "ログインをやめました。Pinshot に戻ってください（このページは閉じてかまいません）。"
        }
        send(status: "200 OK", body: Self.page(message), on: connection)
        finish(.success(callback))
    }

    private func send(status: String, body: String, on connection: NWConnection) {
        let bodyData = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bodyData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// 待っている人に知らせる（2 回目からは何もしない）
    private func finish(_ result: Result<OAuthCallback, Error>) {
        guard received == nil else { return }
        received = result
        waiter?.resume(with: result)
        waiter = nil
    }

    private static func page(_ message: String) -> String {
        """
        <!doctype html><html lang="ja"><head><meta charset="utf-8"><title>Pinshot</title>
        <style>body{font:16px -apple-system,sans-serif;margin:4em auto;max-width:32em;padding:0 1em;color:#333}</style>
        </head><body><p>\(message)</p></body></html>
        """
    }
}

/// 一度だけ通す印（受け口の準備ができた・失敗した、の最初の知らせだけを返す）。
/// 触るのは LoopbackReceiver の queue の上だけなので、鍵は掛けない
private final class ResumeOnce: @unchecked Sendable {
    private var claimed = false

    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
