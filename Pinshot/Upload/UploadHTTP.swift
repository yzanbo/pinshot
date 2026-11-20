import Foundation

/// 保存先との通信（返事の番号を、UploadError に直す）
enum UploadHTTP {
    /// 通信に使うセッション（クッキー・キャッシュを残さない）
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 30 * 60
        configuration.httpAdditionalHeaders = ["User-Agent": "Pinshot"]
        return URLSession(configuration: configuration)
    }()

    /// request を送り、返事の本文を返す（2xx 以外は UploadError）
    static func send(_ request: URLRequest, for destination: UploadDestinationID) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        return try check(data, response, for: destination)
    }

    /// body を本文にして送る（大きい本文はこちら）。progress には、送った割合（0〜1）を渡す
    static func upload(
        _ request: URLRequest,
        body: Data,
        for destination: UploadDestinationID,
        progress: UploadProgress? = nil
    ) async throws -> Data {
        let (data, response) = try await session.upload(for: request, from: body, delegate: progress.map(ProgressDelegate.init))
        return try check(data, response, for: destination)
    }

    /// file を本文にして送る（録画など、メモリに読み込まないもの）
    static func upload(
        _ request: URLRequest,
        file: URL,
        for destination: UploadDestinationID,
        progress: UploadProgress? = nil
    ) async throws -> Data {
        let (data, response) = try await session.upload(for: request, fromFile: file, delegate: progress.map(ProgressDelegate.init))
        return try check(data, response, for: destination)
    }

    /// 送った割合を知らせる
    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
        let progress: UploadProgress

        init(_ progress: @escaping UploadProgress) {
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64,
            totalBytesExpectedToSend: Int64
        ) {
            guard totalBytesExpectedToSend > 0 else { return }
            progress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        }
    }

    /// JSON を読む（読めなければ invalidResponse）
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, for destination: UploadDestinationID) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw UploadError.invalidResponse(destination)
        }
    }

    private static func check(_ data: Data, _ response: URLResponse, for destination: UploadDestinationID) throws -> Data {
        guard let http = response as? HTTPURLResponse else { throw UploadError.invalidResponse(destination) }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw UploadError.notSignedIn(destination)
        case 413: throw UploadError.tooLarge(destination)
        case 429: throw UploadError.rateLimited(destination)
        default: throw UploadError.server(destination, status: http.statusCode, message: errorMessage(in: data))
        }
    }

    /// 保存先が返したエラーの文（Gyazo は message、OAuth は error_description。ほかの保存先の形も見る）
    static func errorMessage(in data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error_summary", "message", "error_description", "error"] {
                if let text = object[key] as? String, !text.isEmpty { return text }
            }
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
