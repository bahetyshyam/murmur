import Foundation
@testable import Murmur

/// Uses a URLProtocol subclass to intercept all URLSession requests —
/// zero real network traffic.
enum TranscriberTests {
    static func run() async {
        Harness.currentSuite = "Transcriber"
        print("▸ Transcriber")

        await Harness.asyncTest("successReturnsText") {
            StubURLProtocol.handler = { _ in
                (Self.http(200), #"{"text":"hello world"}"#.data(using: .utf8)!)
            }
            defer { StubURLProtocol.handler = nil }
            let t = Self.makeTranscriber()
            let text = try await t.transcribe(wav: Data([0x01, 0x02]))
            Harness.expectEqual(text, "hello world")
        }

        await Harness.asyncTest("authErrorOn401") {
            StubURLProtocol.handler = { _ in (Self.http(401), Data()) }
            defer { StubURLProtocol.handler = nil }
            let t = Self.makeTranscriber()
            await Harness.expectThrowsAsync(TranscriberError.auth) {
                _ = try await t.transcribe(wav: Data())
            }
        }

        await Harness.asyncTest("rateLimitOn429") {
            StubURLProtocol.handler = { _ in (Self.http(429), Data()) }
            defer { StubURLProtocol.handler = nil }
            let t = Self.makeTranscriber()
            await Harness.expectThrowsAsync(TranscriberError.rateLimit) {
                _ = try await t.transcribe(wav: Data())
            }
        }

        await Harness.asyncTest("httpErrorWithBodyOnOther5xx") {
            StubURLProtocol.handler = { _ in (Self.http(503), Data("service down".utf8)) }
            defer { StubURLProtocol.handler = nil }
            let t = Self.makeTranscriber()
            do {
                _ = try await t.transcribe(wav: Data())
                Harness.expect(false, "expected throw")
            } catch let TranscriberError.http(status, message) {
                Harness.expectEqual(status, 503)
                Harness.expectEqual(message, "service down")
            } catch {
                Harness.expect(false, "unexpected \(error)")
            }
        }

        await Harness.asyncTest("malformedResponseOn200WithGarbage") {
            StubURLProtocol.handler = { _ in (Self.http(200), Data("not json".utf8)) }
            defer { StubURLProtocol.handler = nil }
            let t = Self.makeTranscriber()
            await Harness.expectThrowsAsync(TranscriberError.malformedResponse) {
                _ = try await t.transcribe(wav: Data())
            }
        }

        await Harness.asyncTest("requestCarriesBearerAndMultipart") {
            let received = LockedValue<URLRequest?>(nil)
            StubURLProtocol.handler = { req in
                received.value = req
                return (Self.http(200), #"{"text":"ok"}"#.data(using: .utf8)!)
            }
            defer { StubURLProtocol.handler = nil }
            let t = Self.makeTranscriber(apiKey: "sk-xyz", model: "whisper-1")
            _ = try await t.transcribe(wav: Data([0xDE, 0xAD, 0xBE, 0xEF]))

            let req = try Harness.unwrap(received.value)
            Harness.expectEqual(req.httpMethod, "POST")
            Harness.expectEqual(req.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
            Harness.expectEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-xyz")
            Harness.expect(req.value(forHTTPHeaderField: "Content-Type")?
                .hasPrefix("multipart/form-data; boundary=") == true)

            let body = Self.readStream(req)
            // isoLatin1 is byte-exact (never fails) — multipart control bytes
            // are ASCII, embedded file bytes may not be valid UTF-8.
            let bodyStr = String(data: body, encoding: .isoLatin1) ?? ""
            Harness.expect(bodyStr.contains(#"name="model""#))
            Harness.expect(bodyStr.contains("whisper-1"))
            Harness.expect(bodyStr.contains(#"name="response_format""#))
            Harness.expect(bodyStr.contains(#"name="file""#))
            Harness.expect(bodyStr.contains(#"filename="audio.wav""#))
            Harness.expect(bodyStr.contains("Content-Type: audio/wav"))
        }

        await Harness.asyncTest("multipartBodyIncludesOptionalPromptAndLanguage") {
            let received = LockedValue<URLRequest?>(nil)
            StubURLProtocol.handler = { req in
                received.value = req
                return (Self.http(200), #"{"text":"ok"}"#.data(using: .utf8)!)
            }
            defer { StubURLProtocol.handler = nil }
            let t = Self.makeTranscriber(biasingPrompt: "Postman API", language: "en")
            _ = try await t.transcribe(wav: Data([0x00]))

            let body = Self.readStream(try Harness.unwrap(received.value))
            // isoLatin1 is byte-exact (never fails) — multipart control bytes
            // are ASCII, embedded file bytes may not be valid UTF-8.
            let bodyStr = String(data: body, encoding: .isoLatin1) ?? ""
            Harness.expect(bodyStr.contains(#"name="prompt""#))
            Harness.expect(bodyStr.contains("Postman API"))
            Harness.expect(bodyStr.contains(#"name="language""#))
            Harness.expect(bodyStr.contains("en"))
        }
    }

    // MARK: - Helpers

    private static func makeTranscriber(
        apiKey: String = "sk-test",
        model: String = "gpt-4o-transcribe",
        biasingPrompt: String = "",
        language: String = ""
    ) -> Transcriber {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return Transcriber(
            apiKey: apiKey,
            model: model,
            biasingPrompt: biasingPrompt,
            language: language,
            session: session
        )
    }

    private static func http(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func readStream(_ req: URLRequest) -> Data {
        // StubURLProtocol.canonicalRequest has already drained the stream
        // into httpBody, so this is trivial now.
        req.httpBody ?? Data()
    }
}

// MARK: - Stubbing primitives

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    /// URLSession consumes `httpBodyStream` before `startLoading` runs, so
    /// we drain it here (where the stream is still fresh) and re-attach the
    /// bytes as `httpBody` so tests can inspect the body.
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        // Drain httpBodyStream here — self.request's stream is still fresh
        // because we're the intercepting protocol (URLSession hasn't sent
        // it anywhere). Re-attach as httpBody for the test to inspect.
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {
            stream.open()
            var data = Data()
            let bufSize = 4096
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            while stream.hasBytesAvailable {
                let read = stream.read(buf, maxLength: bufSize)
                if read <= 0 { break }
                data.append(buf, count: read)
            }
            buf.deallocate()
            stream.close()
            req.httpBody = data
        }
        let (response, data) = handler(req)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Tiny lock wrapper so the URLProtocol callback can hand the captured
/// request back across threads to the test body.
final class LockedValue<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ initial: T) { _value = initial }

    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
