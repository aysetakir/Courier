import Foundation
import Testing
@testable import Courier

/// Token istemeyen uç.
private struct LoginEndpoint: Endpoint {
    var baseURL: URL { URL(string: "https://api.example.com")! }
    var path: String { "/login" }
    var method: HTTPMethod { .post }
    var requiresAuthentication: Bool { false }
}

/// Giden Authorization header'larını sırayla kaydeder.
private final class HeaderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?] = []

    var all: [String?] { lock.withLock { values } }

    func append(_ value: String?) {
        lock.withLock { values.append(value) }
    }
}

@Suite("AuthInterceptor")
struct AuthInterceptorTests {

    private let userJSON = Data(#"{"id":"42","name":"Ayşegül"}"#.utf8)

    /// `acceptedToken` dışındaki her token'a 401 dönen sunucu.
    private func server(accepting acceptedToken: String?, log: HeaderLog) -> URLSession {
        MockURLProtocol.makeSession { [userJSON] request in
            let header = request.value(forHTTPHeaderField: "Authorization")
            log.append(header)
            let accepted = acceptedToken.map { header == "Bearer \($0)" } ?? false
            let response = HTTPURLResponse(
                url: request.url!, statusCode: accepted ? 200 : 401, httpVersion: nil, headerFields: nil
            )!
            return (response, accepted ? userJSON : Data())
        }
    }

    private func makeClient(
        session: URLSession,
        store: InMemoryTokenStore,
        spy: RefreshSpy
    ) -> HTTPClient {
        HTTPClient(
            session: session,
            interceptors: [AuthInterceptor(refresher: TokenRefresher(store: store, spy: spy))],
            retryPolicy: .immediate
        )
    }

    @Test("uçtan uca: 401 → yenile → tekrar → 200")
    func refreshesAndRetriesOnUnauthorized() async throws {
        let log = HeaderLog()
        let spy = RefreshSpy()
        let client = makeClient(
            session: server(accepting: "new-1", log: log),
            store: InMemoryTokenStore(token: .fixture(access: "old")),
            spy: spy
        )

        let user: User = try await client.send(TestAPI.plain)

        #expect(user.id == "42")
        #expect(log.all == ["Bearer old", "Bearer new-1"])
        #expect(await spy.callCount == 1)
    }

    @Test("süresi dolmuş token istek gitmeden yenileniyor")
    func refreshesExpiredTokenBeforeSending() async throws {
        let log = HeaderLog()
        let spy = RefreshSpy()
        let client = makeClient(
            session: server(accepting: "new-1", log: log),
            store: InMemoryTokenStore(token: .fixture(access: "old", expiringIn: -60)),
            spy: spy
        )

        let _: User = try await client.send(TestAPI.plain)

        // Hiç 401 alınmadı: eski token ağa hiç çıkmadı.
        #expect(log.all == ["Bearer new-1"])
        #expect(await spy.callCount == 1)
    }

    @Test("login ucuna Authorization header eklenmiyor")
    func skipsEndpointsWithoutAuthentication() async throws {
        let log = HeaderLog()
        let spy = RefreshSpy()
        // Depo boş: interceptor token isteseydi missingToken fırlardı.
        let client = makeClient(
            session: MockURLProtocol.makeSession { request in
                log.append(request.value(forHTTPHeaderField: "Authorization"))
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (response, Data())
            },
            store: InMemoryTokenStore(),
            spy: spy
        )

        _ = try await client.send(LoginEndpoint())

        #expect(log.all == [nil])
        #expect(await spy.callCount == 0)
    }

    @Test("hep 401 gelirse döngüye girmiyor, istek sayısı sınırlı")
    func doesNotLoopOnPersistentUnauthorized() async throws {
        let log = HeaderLog()
        let spy = RefreshSpy()
        let client = makeClient(
            session: server(accepting: nil, log: log),
            store: InMemoryTokenStore(token: .fixture(access: "old")),
            spy: spy
        )

        await #expect(throws: NetworkError.self) {
            _ = try await client.send(TestAPI.plain)
        }
        #expect(log.all == ["Bearer old", "Bearer new-1"])
        #expect(await spy.callCount == 1)
    }

    @Test("yenileme patlarsa asıl hata dönüyor, tekrar denenmiyor")
    func failedRefreshStopsRetrying() async throws {
        let log = HeaderLog()
        let spy = RefreshSpy(failures: 1)
        let client = makeClient(
            session: server(accepting: "new-2", log: log),
            store: InMemoryTokenStore(token: .fixture(access: "old")),
            spy: spy
        )

        let error = try #require(
            await #expect(throws: NetworkError.self) {
                _ = try await client.send(TestAPI.plain)
            }
        )

        guard case .unauthorized = error else {
            Issue.record("Beklenen .unauthorized, gelen: \(error)")
            return
        }
        #expect(log.all == ["Bearer old"])
    }

    @Test("aynı anda 401 alan 5 istek tek yenilemeyle kurtuluyor")
    func concurrentUnauthorizedRequestsShareRefresh() async throws {
        let log = HeaderLog()
        let spy = RefreshSpy()
        let client = makeClient(
            session: server(accepting: "new-1", log: log),
            store: InMemoryTokenStore(token: .fixture(access: "old")),
            spy: spy
        )

        let users = try await withThrowingTaskGroup(of: User.self) { group in
            for _ in 0..<5 {
                group.addTask { try await client.send(TestAPI.plain) }
            }
            return try await group.reduce(into: [User]()) { $0.append($1) }
        }

        #expect(users.count == 5)
        #expect(await spy.callCount == 1)
        #expect(log.all.filter { $0 == "Bearer new-1" }.count == 5)
    }

    @Test("401 alan POST da tekrar deneniyor")
    func retriesNonIdempotentRequestOnUnauthorized() async throws {
        let log = HeaderLog()
        let spy = RefreshSpy()
        let client = makeClient(
            session: server(accepting: "new-1", log: log),
            store: InMemoryTokenStore(token: .fixture(access: "old")),
            spy: spy
        )

        _ = try await client.send(TestAPI.create(name: "Ayşegül"))

        #expect(log.all == ["Bearer old", "Bearer new-1"])
    }
}
