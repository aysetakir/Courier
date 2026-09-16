import Foundation
import Testing
@testable import Courier

@Suite("RequestInterceptor")
struct InterceptorTests {

    /// Giden isteğin istenen header'larını gövde olarak geri yansıtan session.
    private func echoingSession(_ fields: [String]) -> URLSession {
        MockURLProtocol.makeSession { request in
            let values = fields.map { request.value(forHTTPHeaderField: $0) ?? "" }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(values.joined(separator: "|").utf8))
        }
    }

    @Test("zincirdeki iki interceptor da isteğe dokunuyor")
    func chainsMultipleInterceptors() async throws {
        let client = HTTPClient(
            session: echoingSession(["X-First", "X-Second"]),
            interceptors: [
                HeaderInterceptor(name: "X-First", value: "1"),
                HeaderInterceptor(name: "X-Second", value: "2"),
            ]
        )

        let data = try await client.send(TestAPI.plain)

        #expect(String(decoding: data, as: UTF8.self) == "1|2")
    }

    @Test("interceptor'lar dizideki sırayla uygulanıyor")
    func appliesInterceptorsInOrder() async throws {
        let client = HTTPClient(
            session: echoingSession(["X-Order"]),
            interceptors: [OrderInterceptor(letter: "A"), OrderInterceptor(letter: "B")]
        )

        let data = try await client.send(TestAPI.plain)

        // "AB" olması B'nin A'nın çıktısını gördüğünü kanıtlıyor.
        #expect(String(decoding: data, as: UTF8.self) == "AB")
    }

    @Test("interceptor'ın yazdığı header endpoint'inkini ezebiliyor")
    func interceptorOverridesEndpointHeader() async throws {
        let client = HTTPClient(
            session: echoingSession(["Content-Type"]),
            interceptors: [HeaderInterceptor(name: "Content-Type", value: "application/xml")]
        )

        let data = try await client.send(TestAPI.createV2(name: "Ayşegül"))

        #expect(String(decoding: data, as: UTF8.self) == "application/xml")
    }

    @Test("adapt patlarsa istek hiç gönderilmiyor")
    func failingAdaptPreventsRequest() async throws {
        let counter = CallCounter()
        let session = MockURLProtocol.makeSession { request in
            counter.increment()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        let client = HTTPClient(session: session, interceptors: [FailingInterceptor()])

        await #expect(throws: InterceptorFailure.self) {
            _ = try await client.send(TestAPI.plain)
        }
        #expect(counter.count == 0)
    }

    @Test("varsayılan retry kararı doNotRetry")
    func defaultRetryDecisionIsDoNotRetry() async {
        let interceptor = HeaderInterceptor(name: "X-First", value: "1")

        let decision = await interceptor.retry(
            URLRequest(url: URL(string: "https://api.example.com")!),
            for: TestAPI.plain,
            dueTo: NetworkError.unauthorized,
            attempt: 1
        )

        #expect(decision == .doNotRetry)
    }
}
