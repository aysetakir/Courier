import Foundation
import Testing
@testable import Courier

/// didReceive'e gelen status kodlarını kaydeder.
private actor StatusRecorder: RequestInterceptor {
    private(set) var statusCodes: [Int] = []

    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async {
        statusCodes.append(response.statusCode)
    }
}

@Suite("LoggingInterceptor")
struct LoggingInterceptorTests {

    private func request() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.example.com/users?q=ios")!)
        request.httpMethod = "POST"
        request.setValue("Bearer gizli-token", forHTTPHeaderField: "Authorization")
        request.setValue("session=abc", forHTTPHeaderField: "cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"name":"O'Neil"}"#.utf8)
        return request
    }

    @Test("cURL çıktısında hassas header'lar maskeleniyor")
    func cURLMasksSensitiveHeaders() {
        let curl = LoggingInterceptor.cURL(for: request())

        #expect(!curl.contains("gizli-token"))
        #expect(!curl.contains("session=abc"))
        #expect(curl.contains("'Authorization: ***'"))
        #expect(curl.contains("'Content-Type: application/json'"))
    }

    @Test("cURL çıktısı metodu, gövdeyi ve URL'i içeriyor")
    func cURLContainsRequestParts() {
        let curl = LoggingInterceptor.cURL(for: request())

        #expect(curl.hasPrefix("curl"))
        #expect(curl.contains("-X POST"))
        // Gövdedeki tek tırnak kabuğu bozmayacak şekilde kaçırılmış.
        #expect(curl.contains(#"-d '{"name":"O'\''Neil"}'"#))
        #expect(curl.hasSuffix("'https://api.example.com/users?q=ios'"))
    }

    @Test("GET isteğinde -X ve -d yok")
    func cURLOmitsDefaultsForGet() {
        let curl = LoggingInterceptor.cURL(
            for: URLRequest(url: URL(string: "https://api.example.com/users")!)
        )

        #expect(curl == "curl \\\n  'https://api.example.com/users'")
    }

    @Test("isteği değiştirmiyor ve retry kararına karışmıyor")
    func isPassiveObserver() async throws {
        let interceptor = LoggingInterceptor(logsCURL: true)
        let original = request()

        let adapted = try await interceptor.adapt(original, for: TestAPI.plain)
        let decision = await interceptor.retry(
            original, for: TestAPI.plain, dueTo: NetworkError.unauthorized, attempt: 1
        )

        #expect(adapted == original)
        #expect(decision == .doNotRetry)
    }

    @Test("didReceive her denemenin yanıtını görüyor")
    func didReceiveSeesEveryAttempt() async throws {
        let counter = CallCounter()
        let recorder = StatusRecorder()
        let session = MockURLProtocol.makeSession { request in
            counter.increment()
            let status = counter.count == 1 ? 503 : 200
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }
        let client = HTTPClient(
            session: session,
            interceptors: [LoggingInterceptor(), recorder],
            retryPolicy: .immediate
        )

        _ = try await client.send(TestAPI.plain)

        #expect(await recorder.statusCodes == [503, 200])
    }
}
