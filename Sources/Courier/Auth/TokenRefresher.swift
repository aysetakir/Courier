import Foundation

public enum TokenRefreshError: Error, Equatable {
    /// Depoda hiç token yok: yenilenecek bir şey yok, kullanıcı giriş yapmalı.
    case missingToken
}

/// Geçerli token'ı verir, gerekirse yeniler; aynı anda kaç istek sorarsa
/// sorsun yenileme tek sefer yapılır (single flight).
///
/// Actor: `refreshTask` değişken durum ve eşzamanlı çağrılar onu paylaşıyor.
public actor TokenRefresher {

    /// Refresh token'ı alır, sunucudan yeni token getirir.
    public typealias RefreshAction = @Sendable (_ refreshToken: String) async throws -> AuthToken

    private let store: any TokenStore
    private let refreshAction: RefreshAction
    private let now: @Sendable () -> Date

    /// Devam eden yenileme. Sonradan gelenler yenisini başlatmak yerine bunu bekler.
    private var refreshTask: Task<AuthToken, Error>?

    public init(
        store: any TokenStore,
        now: @escaping @Sendable () -> Date = Date.init,
        refresh: @escaping RefreshAction
    ) {
        self.store = store
        self.now = now
        self.refreshAction = refresh
    }

    /// İstek göndermeden önce: token geçerliyse onu, değilse yenisini döner.
    public func validToken() async throws -> AuthToken {
        if let refreshTask { return try await refreshTask.value }

        let current = try await store.token()
        if let current, !current.isExpired(at: now()) { return current }

        return try await refresh(current)
    }

    /// 401 sonrası: sunucu `rejectedAccessToken`'ı reddetti.
    ///
    /// Aynı anda 5 istek 401 alırsa ilki yeniler; geri kalanlar depoda artık
    /// farklı bir token bulur ve yeniden yenilemez.
    public func refreshAfterRejection(of rejectedAccessToken: String) async throws -> AuthToken {
        if let refreshTask { return try await refreshTask.value }

        let current = try await store.token()
        if let current, current.accessToken != rejectedAccessToken { return current }

        return try await refresh(current)
    }

    private func refresh(_ current: AuthToken?) async throws -> AuthToken {
        // Reentrancy: yukarıdaki `store.token()` beklenirken actor başka
        // çağrılara açıktı; o arada biri yenilemeyi başlatmış olabilir.
        if let refreshTask { return try await refreshTask.value }

        guard let current else { throw TokenRefreshError.missingToken }

        let task = Task { [store, refreshAction] in
            let newToken = try await refreshAction(current.refreshToken)
            try await store.save(newToken)
            return newToken
        }
        // Sıra önemli: önce ata, sonra bekle. Tersi olsaydı bekleme sırasında
        // gelen çağrılar `refreshTask`'ı boş görüp kendi yenilemelerini başlatırdı.
        refreshTask = task
        // Başarı da hata da olsa temizle; yoksa patlamış task sonsuza dek
        // döner ve bir daha hiç yenileme yapılamaz.
        defer { refreshTask = nil }

        return try await task.value
    }
}
