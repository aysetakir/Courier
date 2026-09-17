import Foundation
import Testing
@testable import Courier

@Suite("TokenRefresher")
struct TokenRefresherTests {

    @Test("5 eşzamanlı validToken tek bir yenileme yapıyor, hepsi aynı token'ı alıyor")
    func concurrentCallsShareSingleRefresh() async throws {
        let spy = RefreshSpy()
        let store = InMemoryTokenStore(token: .fixture(expiringIn: -60))
        let refresher = TokenRefresher(store: store, spy: spy)

        let tokens = try await withThrowingTaskGroup(of: AuthToken.self) { group in
            for _ in 0..<5 {
                group.addTask { try await refresher.validToken() }
            }
            return try await group.reduce(into: [AuthToken]()) { $0.append($1) }
        }

        #expect(await spy.callCount == 1)
        #expect(tokens.count == 5)
        #expect(Set(tokens.map(\.accessToken)) == ["new-1"])
        #expect(await store.token()?.accessToken == "new-1")
    }

    @Test("aynı token'ı reddeden 5 eşzamanlı 401 tek bir yenileme yapıyor")
    func concurrentRejectionsShareSingleRefresh() async throws {
        let spy = RefreshSpy()
        let store = InMemoryTokenStore(token: .fixture(access: "old"))
        let refresher = TokenRefresher(store: store, spy: spy)

        let tokens = try await withThrowingTaskGroup(of: AuthToken.self) { group in
            for _ in 0..<5 {
                group.addTask { try await refresher.refreshAfterRejection(of: "old") }
            }
            return try await group.reduce(into: [AuthToken]()) { $0.append($1) }
        }

        #expect(await spy.callCount == 1)
        #expect(Set(tokens.map(\.accessToken)) == ["new-1"])
    }

    @Test("geçerli token varsa yenileme yapılmıyor")
    func validTokenIsReturnedWithoutRefresh() async throws {
        let spy = RefreshSpy()
        let refresher = TokenRefresher(
            store: InMemoryTokenStore(token: .fixture(access: "old")),
            spy: spy
        )

        let token = try await refresher.validToken()

        #expect(token.accessToken == "old")
        #expect(await spy.callCount == 0)
    }

    @Test("depoda token yoksa missingToken fırlatıyor")
    func missingTokenThrows() async throws {
        let spy = RefreshSpy()
        let refresher = TokenRefresher(store: InMemoryTokenStore(), spy: spy)

        await #expect(throws: TokenRefreshError.missingToken) {
            _ = try await refresher.validToken()
        }
        #expect(await spy.callCount == 0)
    }
}
