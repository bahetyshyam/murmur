import Foundation
import OSLog

/// POSTs WAV audio to OpenAI's `/v1/audio/transcriptions` and returns text.
///
/// Designed for injection in tests via a custom `URLSession` whose
/// `URLSessionConfiguration.protocolClasses` includes a stubbing
/// `URLProtocol` subclass. See `TranscriberTests`.
struct Transcriber: Sendable {
    let apiKey: String
    let model: String
    let biasingPrompt: String
    let language: String
    let session: URLSession

    private static let log = Logger(subsystem: "com.local.murmur", category: "transcriber")
    private static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    init(
        apiKey: String,
        model: String,
        biasingPrompt: String = "",
        language: String = "",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.biasingPrompt = biasingPrompt
        self.language = language
        self.session = session
    }

    /// Upload WAV bytes and return the transcribed text.
    func transcribe(wav: Data, filename: String = "audio.wav") async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "----Murmur-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields: [(String, String)] = [
            ("model", model),
            ("response_format", "json"),
        ]
        if !biasingPrompt.isEmpty { fields.append(("prompt", biasingPrompt)) }
        if !language.isEmpty { fields.append(("language", language)) }

        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: fields,
            filename: filename,
            mimeType: "audio/wav",
            fileData: wav
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TranscriberError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriberError.malformedResponse
        }

        switch http.statusCode {
        case 200:
            return try Self.extractText(from: data)
        case 401:
            throw TranscriberError.auth
        case 429:
            throw TranscriberError.rateLimit
        default:
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw TranscriberError.http(status: http.statusCode, message: body)
        }
    }

    // MARK: - Helpers (exposed internal for tests)

    static func multipartBody(
        boundary: String,
        fields: [(String, String)],
        filename: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    static func extractText(from data: Data) throws -> String {
        struct Payload: Decodable { let text: String }
        do {
            return try JSONDecoder().decode(Payload.self, from: data).text
        } catch {
            throw TranscriberError.malformedResponse
        }
    }
}
