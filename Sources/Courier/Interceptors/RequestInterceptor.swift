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
/// İsteği göndermeden önce değiştirir (`adapt`), yanıtı gözlemler
/// (`didReceive`) ve hata sonrası tekrar denenip denenmeyeceğine karar verir
/// (`retry`). Üçünün de varsayılanı var; interceptor yalnızca ilgilendiğini yazar.
public protocol RequestInterceptor: Sendable {

    /// İstek gitmeden önce çağrılır. Zincirdeki her interceptor bir
    /// öncekinin çıktısını alır.
    func adapt(_ request: URLRequest, for endpoint: any Endpoint) async throws -> URLRequest

    /// Sunucudan yanıt geldiğinde, status kodu hataya çevrilmeden önce
    /// çağrılır. Yalnızca gözlem içindir: yanıtı değiştiremez.
    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async

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

    func didReceive(_ response: HTTPURLResponse, data: Data, for request: URLRequest) async {}

    func retry(
        _ request: URLRequest,
        for endpoint: any Endpoint,
        dueTo error: any Error,
        attempt: Int
    ) async -> RetryDecision {
        .doNotRetry
    }
}
