import Foundation
import Testing
@testable import Courier

@Suite("TokenStore")
struct TokenStoreTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func token(expiringIn seconds: TimeInterval) -> AuthToken {
        AuthToken(accessToken: "access", refreshToken: "refresh", expiresAt: now + seconds)
    }

    @Test("29 sn kalan token süresi dolmuş sayılıyor")
    func tokenInsideLeewayIsExpired() {
        #expect(token(expiringIn: 29).isExpired(at: now))
    }

    @Test("tam 30 sn kalan token da süresi dolmuş sayılıyor")
    func tokenAtLeewayBoundaryIsExpired() {
        #expect(token(expiringIn: 30).isExpired(at: now))
    }

    @Test("31 sn kalan token geçerli")
    func tokenOutsideLeewayIsValid() {
        #expect(token(expiringIn: 31).isExpired(at: now) == false)
    }

    @Test("süresi geçmiş token süresi dolmuş sayılıyor")
    func pastTokenIsExpired() {
        #expect(token(expiringIn: -60).isExpired(at: now))
    }

    @Test("store kaydediyor, okuyor ve temizliyor")
    func inMemoryStoreRoundTrip() async {
        let store = InMemoryTokenStore()
        #expect(await store.token() == nil)

        let saved = token(expiringIn: 3600)
        await store.save(saved)
        #expect(await store.token() == saved)

        await store.clear()
        #expect(await store.token() == nil)
    }

    @Test("protokol üzerinden kullanılabiliyor")
    func usableThroughProtocol() async throws {
        let store: any TokenStore = InMemoryTokenStore(token: token(expiringIn: 3600))

        let current = try await store.token()

        #expect(current?.accessToken == "access")
    }
}
