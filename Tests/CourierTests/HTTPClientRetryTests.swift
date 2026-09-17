import Foundation
import Testing
@testable import Courier

@Suite("HTTPClient retry")
struct HTTPClientRetryTests {

    /// Sıradaki status kodunu döner; liste bitince sonuncuda kalır.
    private func sequencedSession(_ statusCodes: [Int], counter: CallCounter) -> URLSession {
        MockURLProtocol.makeSession { request in
            counter.increment()
            let index = min(counter.count, statusCodes.count) - 1
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCodes[index], httpVersion: nil, headerFields: nil
            )!
            return (response, Data(#"{"id":"42","name":"Ayşegül"}"#.utf8))
        }
    }

    @Test("iki 500'den sonra gelen 200 başarıyla dönüyor, tam 3 çağrı yapılıyor")
    func recoversAfterTransientFailures() async throws {
        let counter = CallCounter()
        let client = HTTPClient(
            session: sequencedSession([500, 500, 200], counter: counter),
            retryPolicy: .immediate
        )

        let user: User = try await client.send(TestAPI.plain)

        #expect(user.id == "42")
        #expect(counter.count == 3)
    }

    @Test("hep 500 gelirse maxAttempts'te duruyor")
    func stopsAtMaxAttempts() async throws {
        let counter = CallCounter()
        let client = HTTPClient(
            session: sequencedSession([500], counter: counter),
            retryPolicy: RetryPolicy(maxAttempts: 4, baseDelay: 0, maxDelay: 0, jitter: 0)
        )

        await #expect(throws: NetworkError.self) {
            _ = try await client.send(TestAPI.plain)
        }
        #expect(counter.count == 4)
    }

    @Test("tekrar isteyen interceptor da tavanı aşamıyor")
    func maxAttemptsBindsInterceptors() async throws {
        let counter = CallCounter()
        let client = HTTPClient(
            session: sequencedSession([404], counter: counter),
            interceptors: [AlwaysRetryInterceptor()],
            retryPolicy: .immediate
        )

        await #expect(throws: NetworkError.self) {
            _ = try await client.send(TestAPI.plain)
        }
        #expect(counter.count == RetryPolicy.immediate.maxAttempts)
    }

    @Test("404 tekrar denenmiyor")
    func doesNotRetryClientError() async throws {
        let counter = CallCounter()
        let client = HTTPClient(
            session: sequencedSession([404, 200], counter: counter),
            retryPolicy: .immediate
        )

        await #expect(throws: NetworkError.self) {
            _ = try await client.send(TestAPI.plain)
        }
        #expect(counter.count == 1)
    }

    @Test("500 alan POST varsayılan olarak tekrar denenmiyor")
    func doesNotRetryNonIdempotentMethod() async throws {
        let counter = CallCounter()
        let client = HTTPClient(
            session: sequencedSession([500, 200], counter: counter),
            retryPolicy: .immediate
        )

        await #expect(throws: NetworkError.self) {
            _ = try await client.send(TestAPI.create(name: "Ayşegül"))
        }
        // İkinci çağrı gitseydi sunucuda çift kullanıcı oluşabilirdi.
        #expect(counter.count == 1)
    }

    @Test("iptal edilen istek, interceptor istese bile tekrar denenmiyor")
    func doesNotRetryCancelledRequest() async throws {
        let counter = CallCounter()
        let client = HTTPClient(
            session: MockURLProtocol.makeSession { _ in
                counter.increment()
                throw URLError(.cancelled)
            },
            interceptors: [AlwaysRetryInterceptor()],
            retryPolicy: .immediate
        )

        await #expect(throws: CancellationError.self) {
            _ = try await client.send(TestAPI.plain)
        }
        #expect(counter.count == 1)
    }

    @Test("beklemedeyken iptal edilirse yeni deneme yapılmıyor")
    func cancellationDuringBackoffStopsRetrying() async throws {
        let counter = CallCounter()
        let client = HTTPClient(
            session: sequencedSession([503], counter: counter),
            retryPolicy: RetryPolicy(maxAttempts: 3, baseDelay: 5, maxDelay: 5, jitter: 0)
        )

        let task = Task { try await client.send(TestAPI.plain) }

        // Sabit süre beklemek paralel testlerde yetmiyor: ilk çağrıyı görene kadar bekle.
        while counter.count == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        // Yanıtın işlenip client'ın 5 sn'lik uykuya girmesine pay.
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(counter.count == 1)
    }

    @Test("her denemede istek yeniden adapt ediliyor, header'lar üst üste binmiyor")
    func readaptsOnEveryAttempt() async throws {
        let counter = CallCounter()
        let session = MockURLProtocol.makeSession { request in
            counter.increment()
            let order = request.value(forHTTPHeaderField: "X-Order") ?? ""
            let status = counter.count < 2 ? 500 : 200
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (response, Data(order.utf8))
        }
        let client = HTTPClient(
            session: session,
            interceptors: [OrderInterceptor(letter: "A"), OrderInterceptor(letter: "B")],
            retryPolicy: .immediate
        )

        let data = try await client.send(TestAPI.plain)

        // Önceki turun isteği üzerine adapt edilseydi "ABAB" olurdu.
        #expect(String(decoding: data, as: UTF8.self) == "AB")
        #expect(counter.count == 2)
    }
}
