import Foundation

/// Hata sonrası ne yapılacağı.
public enum RetryDecision: Sendable, Equatable {
    case doNotRetry
    case retry
    /// Belirtilen süre beklendikten sonra tekrar. Sunucu `Retry-After`
    /// gönderdiğinde ya da backoff hesaplandığında kullanılır.
    case retryAfter(TimeInterval)
}

/// Her isteğe uygulanan takılıp çıkarılabilir davranış.
///
/// İki iş yapar: isteği göndermeden önce değiştirmek (`adapt`) ve hata
/// geldikten sonra tekrar denenip denenmeyeceğine karar vermek (`retry`).
public protocol RequestInterceptor: Sendable {

    /// İstek gitmeden önce çağrılır. Zincirdeki her interceptor bir
    /// öncekinin çıktısını alır.
    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest

    /// `attempt`, az önce başarısız olan denemenin sırası (ilk deneme 1).
    func retry(
        _ request: URLRequest,
        for endpoint: any Endpoint,
        dueTo error: any Error,
        attempt: Int
    ) async -> RetryDecision
}

public extension RequestInterceptor {
    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest {
        request
    }

    func retry(
        _ request: URLRequest,
        for endpoint: any Endpoint,
        dueTo error: any Error,
        attempt: Int
    ) async -> RetryDecision {
        .doNotRetry
    }
}
