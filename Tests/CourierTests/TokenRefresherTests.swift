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

    // MARK: - Hata ve temizlik

    @Test("yenileme patlarsa hata 5 bekleyenin hepsine ulaşıyor", .timeLimit(.minutes(1)))
    func refreshFailureReachesAllWaiters() async throws {
        let spy = RefreshSpy(failures: 1)
        let refresher = TokenRefresher(
            store: InMemoryTokenStore(token: .fixture(expiringIn: -60)),
            spy: spy
        )

        // Result'a sarıyoruz ki ilk hata grubu erkenden kapatmasın; hepsini görelim.
        let results = await withTaskGroup(of: Result<AuthToken, any Error>.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do { return .success(try await refresher.validToken()) }
                    catch { return .failure(error) }
                }
            }
            return await group.reduce(into: [Result<AuthToken, any Error>]()) { $0.append($1) }
        }

        // 5 sonuç geldiyse hiçbiri asılı kalmadı; zaman sınırı da bunun sigortası.
        #expect(results.count == 5)
        for result in results {
            guard case .failure(let error) = result else {
                Issue.record("Beklenen hata, gelen: \(result)")
                continue
            }
            #expect(error is RefreshFailure)
        }
        #expect(await spy.callCount == 1)
    }

    @Test("başarısız yenilemeden sonraki çağrı yeniden deneyebiliyor")
    func callAfterFailureStartsNewRefresh() async throws {
        let spy = RefreshSpy(failures: 1)
        let refresher = TokenRefresher(
            store: InMemoryTokenStore(token: .fixture(expiringIn: -60)),
            spy: spy
        )

        await #expect(throws: RefreshFailure.self) {
            _ = try await refresher.validToken()
        }

        // defer temizlemeseydi burada da aynı patlamış task dönerdi.
        let token = try await refresher.validToken()

        #expect(token.accessToken == "new-2")
        #expect(await spy.callCount == 2)
    }

    @Test("yenilemeden sonra token geçerliyse yeni yenileme başlamıyor")
    func noSecondRefreshWhileTokenIsValid() async throws {
        let spy = RefreshSpy()
        let refresher = TokenRefresher(
            store: InMemoryTokenStore(token: .fixture(expiringIn: -60)),
            spy: spy
        )

        _ = try await refresher.validToken()
        let second = try await refresher.validToken()
        // Geç gelen 401: eski token'ı reddediyor ama depo çoktan yenilendi.
        let afterLateRejection = try await refresher.refreshAfterRejection(of: "old")

        #expect(second.accessToken == "new-1")
        #expect(afterLateRejection.accessToken == "new-1")
        #expect(await spy.callCount == 1)
    }

    @Test("güncel token reddedilirse süresi dolmamış olsa da yenileniyor")
    func rejectionOfCurrentTokenForcesRefresh() async throws {
        let spy = RefreshSpy()
        let refresher = TokenRefresher(
            store: InMemoryTokenStore(token: .fixture(access: "old")),
            spy: spy
        )

        let token = try await refresher.refreshAfterRejection(of: "old")

        #expect(token.accessToken == "new-1")
        #expect(await spy.callCount == 1)
    }

    @Test("süre kontrolü enjekte edilen saati kullanıyor")
    func usesInjectedClock() async throws {
        let issuedAt = Date(timeIntervalSince1970: 1_000_000)
        let spy = RefreshSpy()
        let store = InMemoryTokenStore(token: .fixture(expiringIn: 3600, from: issuedAt))
        // Token bir saatlik; saat 59 dk 45 sn ileride → pay içinde, yenilenmeli.
        let refresher = TokenRefresher(
            store: store,
            now: { issuedAt + 3585 },
            refresh: { try await spy.refresh($0) }
        )

        _ = try await refresher.validToken()

        #expect(await spy.callCount == 1)
    }
}
