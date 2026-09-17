import Foundation
@testable import Courier

struct RefreshFailure: Error, Equatable {}

extension AuthToken {
    static func fixture(
        access: String = "old",
        expiringIn seconds: TimeInterval = 3600,
        from now: Date = Date()
    ) -> AuthToken {
        AuthToken(accessToken: access, refreshToken: "refresh-\(access)", expiresAt: now + seconds)
    }
}

/// Sahte refresh ucu: kaç kez çağrıldığını sayar, istenirse ilk N çağrıda patlar.
actor RefreshSpy {
    private(set) var callCount = 0
    private let failures: Int
    private let delay: Duration

    /// Gecikme şart: sıfır olursa yenileme, diğer çağrılar gelmeden biter ve
    /// single flight testi yanlış sebepten yeşil olur.
    init(failures: Int = 0, delay: Duration = .milliseconds(50)) {
        self.failures = failures
        self.delay = delay
    }

    func refresh(_ refreshToken: String) async throws -> AuthToken {
        callCount += 1
        let call = callCount
        try await Task.sleep(for: delay)
        if call <= failures { throw RefreshFailure() }
        return .fixture(access: "new-\(call)")
    }
}

extension TokenRefresher {
    init(store: any TokenStore, spy: RefreshSpy) {
        self.init(store: store) { try await spy.refresh($0) }
    }
}
