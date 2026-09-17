import Foundation

public struct AuthToken: Sendable, Equatable, Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    /// Süresi bitmek üzere olan token'ı da bitmiş sayıyoruz: istek sunucuya
    /// varana kadar geçen sürede ölürse boşuna 401 alırız.
    public static let expirationLeeway: TimeInterval = 30

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// `now` dışarıdan veriliyor ki testler saate bağımlı olmasın.
    public func isExpired(at now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) <= Self.expirationLeeway
    }
}

/// Token'ın nerede tutulduğunu soyutlar: uygulamada Keychain, testte bellek.
///
/// Metotlar `throws`: Keychain gibi gerçek depolar hata verebilir. Hata
/// vermeyen uygulamalar (`InMemoryTokenStore`) `throws` yazmadan uyabilir.
public protocol TokenStore: Sendable {
    func token() async throws -> AuthToken?
    func save(_ token: AuthToken) async throws
    func clear() async throws
}

/// Değişken durum var ve aynı anda birden çok istek okuyup yazabilir: actor.
public actor InMemoryTokenStore: TokenStore {
    private var storedToken: AuthToken?

    public init(token: AuthToken? = nil) {
        self.storedToken = token
    }

    public func token() -> AuthToken? {
        storedToken
    }

    public func save(_ token: AuthToken) {
        storedToken = token
    }

    public func clear() {
        storedToken = nil
    }
}
