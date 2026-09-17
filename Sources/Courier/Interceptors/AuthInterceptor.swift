import Foundation

/// İsteğe Bearer token ekler; 401 gelirse token'ı yenileyip bir kez daha dener.
public struct AuthInterceptor: RequestInterceptor {

    private static let scheme = "Bearer "

    private let refresher: TokenRefresher

    public init(refresher: TokenRefresher) {
        self.refresher = refresher
    }

    public func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        // Login gibi uçlar token'sız gider; burada token istemek, henüz giriş
        // yapmamış kullanıcıyı missingToken hatasına düşürürdü.
        guard endpoint.requiresAuthentication else { return request }

        let token = try await refresher.validToken()
        var request = request
        request.setValue(Self.scheme + token.accessToken, forHTTPHeaderField: "Authorization")
        return request
    }

    /// Yalnızca ilk denemedeki 401'de tekrar ister: yenilenmiş token da
    /// reddedildiyse sorun token'da değildir, döngüye girmenin anlamı yok.
    ///
    /// Tekrar deneme `RetryPolicy.maxAttempts` en az 2 iken mümkün.
    public func retry(
        _ request: URLRequest,
        for endpoint: any Endpoint,
        dueTo error: any Error,
        attempt: Int
    ) async -> RetryDecision {
        guard
            endpoint.requiresAuthentication,
            attempt == 1,
            let networkError = error as? NetworkError,
            case .unauthorized = networkError,
            let header = request.value(forHTTPHeaderField: "Authorization"),
            header.hasPrefix(Self.scheme)
        else { return .doNotRetry }

        let rejectedToken = String(header.dropFirst(Self.scheme.count))
        do {
            // Yeni token'ı burada kullanmıyoruz: client tekrar denerken isteği
            // yeniden adapt ediyor, header oradan güncel geliyor.
            _ = try await refresher.refreshAfterRejection(of: rejectedToken)
            // 401 sunucunun isteği işlemediği anlamına gelir; POST da olsa güvenli.
            return .retry
        } catch {
            return .doNotRetry
        }
    }
}
